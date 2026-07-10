import Foundation

/// A ranked recent-session row for the Sessions & Timeline tab.
public struct SessionSummary: Sendable, Equatable, Identifiable {
    public var id: String { sessionId }
    public let sessionId: String
    /// Claude Code's generated title for the session, when known; `nil` falls back to
    /// the session ID in the UI.
    public let title: String?
    public let project: String
    public let totals: TokenTotals
    public let costUSD: Double
    public let firstActivity: Date
    public let lastActivity: Date
    public init(sessionId: String, title: String? = nil, project: String, totals: TokenTotals,
                costUSD: Double, firstActivity: Date, lastActivity: Date) {
        self.sessionId = sessionId; self.title = title; self.project = project; self.totals = totals
        self.costUSD = costUSD; self.firstActivity = firstActivity; self.lastActivity = lastActivity
    }
}

/// One summary per session active in `range`, sorted most-recent-first. Project
/// is taken from the session's latest event; cost is derived from the price table.
/// `titles` maps `sessionId → title` (from Claude Code `ai-title` lines).
public func sessionSummaries(events: [UsageEvent], range: TimeRange, now: Date,
                             prices: PriceTable, titles: [String: String] = [:]) -> [SessionSummary] {
    sessionSummaries(deduped: deduplicated(events), range: range, now: now,
                     prices: prices, titles: titles)
}

/// As `sessionSummaries(events:…)` but for already-`deduplicated` events, so the
/// detail window can share a single dedup pass across all its builders.
public func sessionSummaries(deduped events: [UsageEvent], range: TimeRange, now: Date,
                             prices: PriceTable, titles: [String: String] = [:]) -> [SessionSummary] {
    let interval = range.interval(now: now)

    struct Acc {
        var project: String
        var totals = TokenTotals.zero
        var cost = 0.0
        var first: Date
        var last: Date
    }
    var byId: [String: Acc] = [:]

    for e in events {
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
        SessionSummary(sessionId: id, title: titles[id], project: a.project, totals: a.totals,
                       costUSD: a.cost, firstActivity: a.first, lastActivity: a.last)
    }
    .sorted { $0.lastActivity > $1.lastActivity }
}
