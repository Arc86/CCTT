import Foundation

/// The fractional change in total tokens for `range` versus the immediately
/// preceding equal-length window — e.g. the last 5 hours against the 5 hours
/// before that. Used by the detail window's hero to show a trend pill.
///
/// Returns `nil` when there is no honest comparison to make:
/// - `.all` has no earlier window (unbounded lower edge).
/// - `.thisWeek` is a *partial* week, so a full-length preceding window would
///   compare unlike spans; we decline rather than mislead.
/// - the preceding window had zero tokens, so there is no baseline to divide by.
///
/// A positive value means usage rose versus the previous window; negative means
/// it fell. `+0.12` is "12% more than the previous period".
public func tokenDelta(events: [UsageEvent], range: TimeRange, now: Date) -> Double? {
    tokenDelta(deduped: deduplicated(events), range: range, now: now)
}

/// As `tokenDelta(events:…)` but for already-`deduplicated` events, so the detail
/// window can share its single dedup pass across every builder.
public func tokenDelta(deduped events: [UsageEvent], range: TimeRange, now: Date) -> Double? {
    // `.all` → no bounded window, so no "previous period" exists.
    guard let current = range.interval(now: now) else { return nil }
    // A partial calendar week can't be compared to a full previous window honestly.
    if range == .thisWeek { return nil }

    let length = current.duration
    let previous = DateInterval(start: current.start.addingTimeInterval(-length),
                                end: current.start)

    var currentTokens = 0
    var previousTokens = 0
    for e in events {
        let t = e.timestamp
        // Order matters: the two windows share only the single boundary instant,
        // and an event exactly on it counts toward the current window.
        if current.contains(t) {
            currentTokens += e.totals.total
        } else if previous.contains(t) {
            previousTokens += e.totals.total
        }
    }

    guard previousTokens > 0 else { return nil }
    return (Double(currentTokens) - Double(previousTokens)) / Double(previousTokens)
}
