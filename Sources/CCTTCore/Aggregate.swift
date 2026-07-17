import Foundation

/// Keep one event per `dedupKey`, choosing the **last** occurrence; events
/// lacking a key are always kept. Shared by `aggregate` and the on-demand
/// detail-window builders so every consumer counts each `(requestId, messageId)`
/// exactly once.
///
/// Last-wins matters: Claude Code emits a message across several JSONL lines as it
/// streams, all sharing one `message.id`. Earlier lines carry a placeholder usage
/// (often `output_tokens == 1`); only the final line has the true tally. Verified
/// against real logs: ~18k of 27k messages repeat, ~4k with differing usage, and
/// in every case only `output_tokens` grows. Keeping the first line would
/// systematically undercount output tokens (and derived cost).
func deduplicated(_ events: [UsageEvent]) -> [UsageEvent] {
    var latestByKey: [String: UsageEvent] = [:]
    var keyOrder: [String] = []
    var keyless: [UsageEvent] = []
    for e in events {
        guard let key = e.dedupKey else { keyless.append(e); continue }
        if latestByKey[key] == nil { keyOrder.append(key) }
        latestByKey[key] = e   // last occurrence wins
    }
    var unique = keyOrder.map { latestByKey[$0]! }
    unique.append(contentsOf: keyless)
    return unique
}

/// Pure aggregation: de-duplicated events → grouped, sorted rollups.
public func aggregate(events: [UsageEvent], parseErrors: Int, now: Date) -> UsageSnapshot {
    let unique = deduplicated(events)
    let blocks = SessionBlocks.segment(unique)
    let currentBlock = SessionBlocks.current(blocks, now: now)

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
        fiveHour: currentBlock?.totals ?? .zero,
        fiveHourBlock: currentBlock,
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
