import Foundation

/// Pure aggregation: de-duplicated events → grouped, sorted rollups.
public func aggregate(events: [UsageEvent], parseErrors: Int, now: Date) -> UsageSnapshot {
    // De-dup: keep one event per dedupKey; nil-key events are always kept.
    var seen = Set<String>()
    var unique: [UsageEvent] = []
    unique.reserveCapacity(events.count)
    for e in events {
        if let key = e.dedupKey {
            if seen.insert(key).inserted { unique.append(e) }
        } else {
            unique.append(e)
        }
    }

    let fiveHourStart = now.addingTimeInterval(-5 * 3600)
    let weeklyStart = now.addingTimeInterval(-7 * 24 * 3600)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now

    var overall = TokenTotals.zero
    var project: [String: TokenTotals] = [:]
    var model: [String: TokenTotals] = [:]
    var session: [String: TokenTotals] = [:]
    var agentKind: [String: TokenTotals] = [:]
    var skill: [String: TokenTotals] = [:]
    var plugin: [String: TokenTotals] = [:]
    var fiveHour = TokenTotals.zero
    var weekly = TokenTotals.zero
    var monthToDate = TokenTotals.zero
    var monthModel: [String: TokenTotals] = [:]

    for e in unique {
        let t = e.totals
        overall += t
        project[e.project, default: .zero] += t
        model[e.model, default: .zero] += t
        session[e.sessionId, default: .zero] += t
        agentKind[e.agentKind, default: .zero] += t
        if let s = e.skill { skill[s, default: .zero] += t }
        if let p = e.plugin { plugin[p, default: .zero] += t }
        if e.timestamp > fiveHourStart { fiveHour += t }
        if e.timestamp > weeklyStart { weekly += t }
        if e.timestamp >= monthStart {
            monthToDate += t
            monthModel[e.model, default: .zero] += t
        }
    }

    return UsageSnapshot(
        overall: overall,
        byProject: sortedRollups(project),
        byModel: sortedRollups(model),
        bySession: sortedRollups(session),
        byAgentKind: sortedRollups(agentKind),
        bySkill: sortedRollups(skill),
        byPlugin: sortedRollups(plugin),
        fiveHour: fiveHour,
        weekly: weekly,
        monthToDate: monthToDate,
        monthByModel: sortedRollups(monthModel),
        parseErrors: parseErrors,
        generatedAt: now
    )
}

/// Sort by total tokens descending, ties broken by key ascending for stability.
private func sortedRollups(_ dict: [String: TokenTotals]) -> [Rollup] {
    dict.map { Rollup(key: $0.key, totals: $0.value) }
        .sorted { a, b in
            a.totals.total != b.totals.total
                ? a.totals.total > b.totals.total
                : a.key < b.key
        }
}
