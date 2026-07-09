import Foundation

/// A ranked recent-session row for the Sessions & Timeline tab.
public struct SessionSummary: Sendable, Equatable, Identifiable {
    public var id: String { sessionId }
    public let sessionId: String
    public let project: String
    public let totals: TokenTotals
    public let costUSD: Double
    public let firstActivity: Date
    public let lastActivity: Date
    public init(sessionId: String, project: String, totals: TokenTotals, costUSD: Double,
                firstActivity: Date, lastActivity: Date) {
        self.sessionId = sessionId; self.project = project; self.totals = totals
        self.costUSD = costUSD; self.firstActivity = firstActivity; self.lastActivity = lastActivity
    }
}

/// One summary per session active in `range`, sorted most-recent-first. Project
/// is taken from the session's latest event; cost is derived from the price table.
public func sessionSummaries(events: [UsageEvent], range: TimeRange, now: Date,
                             prices: PriceTable) -> [SessionSummary] {
    let interval = range.interval(now: now)

    struct Acc {
        var project: String
        var totals = TokenTotals.zero
        var cost = 0.0
        var first: Date
        var last: Date
    }
    var byId: [String: Acc] = [:]

    for e in deduplicated(events) {
        if let interval, !interval.contains(e.timestamp) { continue }
        let c = prices.price(forModel: e.model)?.costUSD(for: e.totals) ?? 0
        if var acc = byId[e.sessionId] {
            acc.totals += e.totals
            acc.cost += c
            if e.timestamp < acc.first { acc.first = e.timestamp }
            if e.timestamp > acc.last { acc.last = e.timestamp; acc.project = e.project }
            byId[e.sessionId] = acc
        } else {
            byId[e.sessionId] = Acc(project: e.project, totals: e.totals, cost: c,
                                    first: e.timestamp, last: e.timestamp)
        }
    }

    return byId.map { id, a in
        SessionSummary(sessionId: id, project: a.project, totals: a.totals, costUSD: a.cost,
                       firstActivity: a.first, lastActivity: a.last)
    }
    .sorted { $0.lastActivity > $1.lastActivity }
}
