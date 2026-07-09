import Foundation

/// One grouped bucket with both its measured tokens and its derived ($) cost.
public struct CostedRollup: Sendable, Equatable {
    public let key: String
    public let totals: TokenTotals
    public let costUSD: Double
    public init(key: String, totals: TokenTotals, costUSD: Double) {
        self.key = key; self.totals = totals; self.costUSD = costUSD
    }
}

/// A time-range slice of usage, grouped across every dimension the detail tabs
/// need, with per-bucket derived cost. The single source of $ for the UI.
public struct Breakdown: Sendable, Equatable {
    public let byProject: [CostedRollup]
    public let byModel: [CostedRollup]
    public let byAgentKind: [CostedRollup]
    public let bySkill: [CostedRollup]
    public let byPlugin: [CostedRollup]
    public let bySession: [CostedRollup]
    public let totals: TokenTotals
    public let totalCostUSD: Double

    public init(byProject: [CostedRollup], byModel: [CostedRollup], byAgentKind: [CostedRollup],
                bySkill: [CostedRollup], byPlugin: [CostedRollup], bySession: [CostedRollup],
                totals: TokenTotals, totalCostUSD: Double) {
        self.byProject = byProject; self.byModel = byModel; self.byAgentKind = byAgentKind
        self.bySkill = bySkill; self.byPlugin = byPlugin; self.bySession = bySession
        self.totals = totals; self.totalCostUSD = totalCostUSD
    }

    public static let empty = Breakdown(byProject: [], byModel: [], byAgentKind: [],
                                        bySkill: [], byPlugin: [], bySession: [],
                                        totals: .zero, totalCostUSD: 0)
}

/// Token + derived-cost accumulator for one dimension key, summed as events are scanned.
private struct CostAcc { var totals = TokenTotals.zero; var cost = 0.0 }

/// Build a costed `Breakdown` for `range`. De-duplicates, filters to the range's
/// interval (`.all` → no bound), then in a single pass accumulates each event's
/// tokens and its exact derived cost (`prices.price(model)?.costUSD ?? 0`) into
/// every dimension. Dimensions are sorted by descending token total (ties by key).
public func breakdown(events: [UsageEvent], range: TimeRange, now: Date,
                      prices: PriceTable) -> Breakdown {
    let interval = range.interval(now: now)
    var overall = TokenTotals.zero
    var overallCost = 0.0
    var project: [String: CostAcc] = [:]
    var model: [String: CostAcc] = [:]
    var agentKind: [String: CostAcc] = [:]
    var skill: [String: CostAcc] = [:]
    var plugin: [String: CostAcc] = [:]
    var session: [String: CostAcc] = [:]

    func add(_ dict: inout [String: CostAcc], _ key: String, _ t: TokenTotals, _ c: Double) {
        var acc = dict[key] ?? CostAcc()
        acc.totals += t; acc.cost += c
        dict[key] = acc
    }

    for e in deduplicated(events) {
        if let interval, !interval.contains(e.timestamp) { continue }
        let t = e.totals
        let c = prices.price(forModel: e.model)?.costUSD(for: t) ?? 0
        overall += t; overallCost += c
        add(&project, e.project, t, c)
        add(&model, e.model, t, c)
        add(&agentKind, e.agentKind, t, c)
        add(&session, e.sessionId, t, c)
        if let s = e.skill { add(&skill, s, t, c) }
        if let p = e.plugin { add(&plugin, p, t, c) }
    }

    return Breakdown(byProject: sortedCosted(project), byModel: sortedCosted(model),
                     byAgentKind: sortedCosted(agentKind), bySkill: sortedCosted(skill),
                     byPlugin: sortedCosted(plugin), bySession: sortedCosted(session),
                     totals: overall, totalCostUSD: overallCost)
}

/// Sort by total tokens descending, ties broken by key ascending (stable UI order).
private func sortedCosted(_ dict: [String: CostAcc]) -> [CostedRollup] {
    dict.map { CostedRollup(key: $0.key, totals: $0.value.totals, costUSD: $0.value.cost) }
        .sorted { a, b in
            a.totals.total != b.totals.total ? a.totals.total > b.totals.total : a.key < b.key
        }
}
