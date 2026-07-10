import Foundation

/// Anthropic's weekly-limit heavy-usage band, drawn as a reference region on the
/// hour-of-day chart. This is a community heuristic (weekday mornings, Pacific),
/// not an authoritative value — it may drift, so the UI labels it as estimated.
public struct ThrottleWindow: Sendable, Equatable {
    public let timeZoneID: String
    public let startHour: Int   // inclusive
    public let endHour: Int     // exclusive

    public init(timeZoneID: String, startHour: Int, endHour: Int) {
        self.timeZoneID = timeZoneID; self.startHour = startHour; self.endHour = endHour
    }

    public static let anthropicWeekly = ThrottleWindow(
        timeZoneID: "America/Los_Angeles", startHour: 5, endHour: 11)
}

/// One hour-of-day slot, aggregated across every day in range.
public struct HourBucket: Sendable, Equatable, Identifiable {
    public let hour: Int            // 0...23 in the profile's timezone
    public let totals: TokenTotals
    public let activeDays: Int      // distinct local days that had usage this hour
    public let inThrottleWindow: Bool
    public var id: Int { hour }

    public init(hour: Int, totals: TokenTotals, activeDays: Int, inThrottleWindow: Bool) {
        self.hour = hour; self.totals = totals
        self.activeDays = activeDays; self.inThrottleWindow = inThrottleWindow
    }

    /// Average tokens on the days this hour was actually used — a fairer "typical
    /// hour" than a flat total that a single busy day would dominate.
    public var averageTokensPerActiveDay: Double {
        activeDays > 0 ? Double(totals.total) / Double(activeDays) : 0
    }
}

/// Profile usage by hour-of-day (0...23) in `timeZone`, aggregated over every day
/// in `range`. Always returns all 24 buckets (empty hours included) so the chart
/// x-axis is complete. Hour-of-day is a local display concern, so this uses the
/// injected `timeZone` (default current) rather than the UTC boundaries the
/// window rollups use. Each bucket is flagged if it falls inside `throttle`,
/// converted from the window's timezone to `timeZone` using the current UTC
/// offsets (approximate across DST — it's a visual reference band, not billing).
public func hourlyProfile(events: [UsageEvent], range: TimeRange, now: Date,
                          timeZone: TimeZone = .current,
                          throttle: ThrottleWindow = .anthropicWeekly) -> [HourBucket] {
    hourlyProfile(deduped: deduplicated(events), range: range, now: now,
                  timeZone: timeZone, throttle: throttle)
}

/// As `hourlyProfile(events:…)` but for already-`deduplicated` events, so the
/// detail window can share a single dedup pass across all its builders.
public func hourlyProfile(deduped events: [UsageEvent], range: TimeRange, now: Date,
                          timeZone: TimeZone = .current,
                          throttle: ThrottleWindow = .anthropicWeekly) -> [HourBucket] {
    let interval = range.interval(now: now)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timeZone

    var totals = Array(repeating: TokenTotals.zero, count: 24)
    var days: [Set<Date>] = Array(repeating: [], count: 24)   // distinct local days per hour

    for e in events {
        if let interval, !interval.contains(e.timestamp) { continue }
        let hour = cal.component(.hour, from: e.timestamp)
        totals[hour] += e.totals
        days[hour].insert(cal.startOfDay(for: e.timestamp))
    }

    let throttleHours = localThrottleHours(throttle, in: timeZone, now: now)
    return (0..<24).map { h in
        HourBucket(hour: h, totals: totals[h], activeDays: days[h].count,
                   inThrottleWindow: throttleHours.contains(h))
    }
}

/// The throttle window's hours expressed in `timeZone`, shifted by the current
/// offset difference between the window's zone and `timeZone`.
private func localThrottleHours(_ window: ThrottleWindow, in timeZone: TimeZone,
                                now: Date) -> Set<Int> {
    guard window.endHour > window.startHour,
          let windowZone = TimeZone(identifier: window.timeZoneID) else { return [] }
    let shift = (timeZone.secondsFromGMT(for: now) - windowZone.secondsFromGMT(for: now)) / 3600
    var hours = Set<Int>()
    for h in window.startHour..<window.endHour {
        hours.insert(((h + shift) % 24 + 24) % 24)
    }
    return hours
}
