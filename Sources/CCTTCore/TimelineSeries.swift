import Foundation

/// One fixed-width slot of spend-over-time for the timeline chart.
public struct TimeBucket: Sendable, Equatable {
    public let start: Date
    public let totals: TokenTotals
    public let costUSD: Double
    public init(start: Date, totals: TokenTotals, costUSD: Double) {
        self.start = start; self.totals = totals; self.costUSD = costUSD
    }
}

/// Bucket the range's events into evenly-spaced slots (granularity chosen from
/// the range). Empty slots are included as zero buckets so the chart's x-axis is
/// continuous. `.all` starts at the earliest event's UTC day; with no events it
/// returns an empty series.
public func timelineSeries(events: [UsageEvent], range: TimeRange, now: Date,
                           prices: PriceTable) -> [TimeBucket] {
    timelineSeries(deduped: deduplicated(events), range: range, now: now, prices: prices)
}

/// As `timelineSeries(events:…)` but for already-`deduplicated` events, so the
/// detail window can share a single dedup pass across all its builders.
public func timelineSeries(deduped unique: [UsageEvent], range: TimeRange, now: Date,
                           prices: PriceTable) -> [TimeBucket] {
    let g = bucketSeconds(for: range)

    let lower: Date
    if let interval = range.interval(now: now) {
        lower = interval.start
    } else {
        guard let earliest = unique.map(\.timestamp).min() else { return [] }
        lower = startOfUTCDay(earliest)
    }

    let span = now.timeIntervalSince(lower)
    guard span >= 0 else { return [] }
    let count = max(1, Int(ceil(span / g)))

    var totals = Array(repeating: TokenTotals.zero, count: count)
    var costs = Array(repeating: 0.0, count: count)
    for e in unique where e.timestamp >= lower && e.timestamp <= now {
        let idx = min(count - 1, max(0, Int(e.timestamp.timeIntervalSince(lower) / g)))
        totals[idx] += e.totals
        costs[idx] += prices.price(forModel: e.model)?.costUSD(for: e.totals) ?? 0
    }

    return (0..<count).map { i in
        TimeBucket(start: lower.addingTimeInterval(Double(i) * g),
                   totals: totals[i], costUSD: costs[i])
    }
}

/// Slot width in seconds: fine for short ranges, coarse for long ones.
private func bucketSeconds(for range: TimeRange) -> TimeInterval {
    switch range {
    case .fiveHour:               return 15 * 60
    case .thisWeek, .last7Days:   return 3600
    case .last30Days, .all:       return 86_400
    }
}

private func startOfUTCDay(_ date: Date) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.startOfDay(for: date)
}
