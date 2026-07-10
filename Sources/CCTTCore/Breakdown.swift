import Foundation

/// One grouped bucket with both its measured tokens and its derived ($) cost.
public struct CostedRollup: Sendable, Equatable {
    public let key: String
    public let totals: TokenTotals
    public let costUSD: Double
    /// Tokens whose model has no known price, so they contribute 0 to `costUSD`.
    /// Kept explicit so the UI can render "n/a" instead of a misleading "$0" — a
    /// silent $0 would violate CCTT's "provenance is always explicit" principle.
    public let unpricedTokens: Int

    public init(key: String, totals: TokenTotals, costUSD: Double, unpricedTokens: Int = 0) {
        self.key = key; self.totals = totals; self.costUSD = costUSD
        self.unpricedTokens = unpricedTokens
    }

    /// No token in this bucket could be priced → show "n/a", not "$0".
    public var costUnavailable: Bool { totals.total > 0 && unpricedTokens == totals.total }
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
    public let byBranch: [CostedRollup]      // git branch (events lacking one are excluded)
    public let totals: TokenTotals
    public let totalCostUSD: Double
    /// Tokens across the whole range whose model had no known price. When > 0 the
    /// `totalCostUSD` figure is a lower bound; the UI flags the total as partial.
    public let unpricedTokens: Int

    public init(byProject: [CostedRollup], byModel: [CostedRollup], byAgentKind: [CostedRollup],
                bySkill: [CostedRollup], byPlugin: [CostedRollup], bySession: [CostedRollup],
                byBranch: [CostedRollup] = [],
                totals: TokenTotals, totalCostUSD: Double, unpricedTokens: Int = 0) {
        self.byProject = byProject; self.byModel = byModel; self.byAgentKind = byAgentKind
        self.bySkill = bySkill; self.byPlugin = byPlugin; self.bySession = bySession
        self.byBranch = byBranch
        self.totals = totals; self.totalCostUSD = totalCostUSD
        self.unpricedTokens = unpricedTokens
    }

    /// Distinct sessions active in range (for the "sessions" stat card).
    public var sessionCount: Int { bySession.count }
    /// Assistant turns in range (for the "turns" stat card).
    public var turnCount: Int { totals.eventCount }

    /// The `totalCostUSD` omits some real usage because a model wasn't priced.
    public var costPartial: Bool { unpricedTokens > 0 && unpricedTokens < totals.total }
    /// No usage in range could be priced at all.
    public var costUnavailable: Bool { totals.total > 0 && unpricedTokens == totals.total }

    public static let empty = Breakdown(byProject: [], byModel: [], byAgentKind: [],
                                        bySkill: [], byPlugin: [], bySession: [],
                                        totals: .zero, totalCostUSD: 0)
}

/// Token + derived-cost accumulator for one dimension key, summed as events are scanned.
private struct CostAcc { var totals = TokenTotals.zero; var cost = 0.0; var unpriced = 0 }

/// Build a costed `Breakdown` for `range`. De-duplicates, filters to the range's
/// interval (`.all` → no bound), then in a single pass accumulates each event's
/// tokens and its exact derived cost (`prices.price(model)?.costUSD ?? 0`) into
/// every dimension. Dimensions are sorted by descending token total (ties by key).
public func breakdown(events: [UsageEvent], range: TimeRange, now: Date,
                      prices: PriceTable) -> Breakdown {
    breakdown(deduped: deduplicated(events), range: range, now: now, prices: prices)
}

/// As `breakdown(events:…)` but for events already run through `deduplicated`.
/// The detail window shares one dedup pass across every builder (it's range- and
/// price-independent), so this variant skips repeating that ~O(n) work per tab.
public func breakdown(deduped events: [UsageEvent], range: TimeRange, now: Date,
                      prices: PriceTable) -> Breakdown {
    let interval = range.interval(now: now)
    var overall = TokenTotals.zero
    var overallCost = 0.0
    var overallUnpriced = 0
    var project: [String: CostAcc] = [:]
    var model: [String: CostAcc] = [:]
    var agentKind: [String: CostAcc] = [:]
    var skill: [String: CostAcc] = [:]
    var plugin: [String: CostAcc] = [:]
    var session: [String: CostAcc] = [:]
    var branch: [String: CostAcc] = [:]

    func add(_ dict: inout [String: CostAcc], _ key: String,
             _ t: TokenTotals, _ c: Double, _ u: Int) {
        var acc = dict[key] ?? CostAcc()
        acc.totals += t; acc.cost += c; acc.unpriced += u
        dict[key] = acc
    }

    for e in events {
        if let interval, !interval.contains(e.timestamp) { continue }
        let t = e.totals
        let priced = prices.price(forModel: e.model)
        let c = priced?.costUSD(for: t) ?? 0
        let u = priced == nil ? t.total : 0    // unpriced model → its tokens carry no cost
        overall += t; overallCost += c; overallUnpriced += u
        add(&project, e.project, t, c, u)
        add(&model, e.model, t, c, u)
        add(&agentKind, e.agentKind, t, c, u)
        add(&session, e.sessionId, t, c, u)
        if let s = e.skill { add(&skill, s, t, c, u) }
        if let p = e.plugin { add(&plugin, p, t, c, u) }
        if let br = e.gitBranch, !br.isEmpty { add(&branch, br, t, c, u) }
    }

    return Breakdown(byProject: sortedCosted(project), byModel: sortedCosted(model),
                     byAgentKind: sortedCosted(agentKind), bySkill: sortedCosted(skill),
                     byPlugin: sortedCosted(plugin), bySession: sortedCosted(session),
                     byBranch: sortedCosted(branch),
                     totals: overall, totalCostUSD: overallCost, unpricedTokens: overallUnpriced)
}

/// Sort by total tokens descending, ties broken by key ascending (stable UI order).
private func sortedCosted(_ dict: [String: CostAcc]) -> [CostedRollup] {
    dict.map { CostedRollup(key: $0.key, totals: $0.value.totals,
                            costUSD: $0.value.cost, unpricedTokens: $0.value.unpriced) }
        .sorted { a, b in
            a.totals.total != b.totals.total ? a.totals.total > b.totals.total : a.key < b.key
        }
}
