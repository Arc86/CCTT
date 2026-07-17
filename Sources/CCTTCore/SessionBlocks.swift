import Foundation

/// One anchored 5-hour usage window ("session block"), the way Claude meters it:
/// the window opens with your first message and runs a fixed 5 hours, rather than
/// trailing `now`. `end` is always `start + SessionBlocks.duration`.
public struct SessionBlock: Sendable, Equatable {
    /// The block's first event's timestamp, floored to the hour (UTC).
    public let start: Date
    public let end: Date
    public let totals: TokenTotals

    public init(start: Date, end: Date, totals: TokenTotals) {
        self.start = start; self.end = end; self.totals = totals
    }
}

/// Segments usage events into anchored 5-hour blocks.
///
/// The rule is `ccusage`'s, adopted because it matches observed Claude behaviour
/// far better than a trailing `now - 5h` cutoff does. The hour-flooring in
/// particular is a **heuristic** — we cannot prove Claude floors to the hour. When
/// a live `reset_at` is available it always wins over this (see `LimitEngine`).
public enum SessionBlocks {
    public static let duration: TimeInterval = 5 * 3600

    /// Segment de-duplicated events into blocks, oldest first.
    ///
    /// A block opens at its first event's timestamp floored to the hour and closes
    /// when an event arrives `duration` or more after that start — the window aged
    /// out. The boundary is half-open: an event exactly at `start + duration` opens
    /// the next block. Input need not be sorted.
    ///
    /// Ageing out is the *only* rule. Going idle does not reset the window: Claude's
    /// five hours are wall-clock from the first message, so a long quiet stretch
    /// inside a block leaves it open.
    public static func segment(_ deduped: [UsageEvent]) -> [SessionBlock] {
        let sorted = deduped.sorted { $0.timestamp < $1.timestamp }
        var blocks: [SessionBlock] = []
        var start: Date?
        var totals = TokenTotals.zero

        for e in sorted {
            let opensNewBlock: Bool = {
                guard let start else { return true }
                return e.timestamp.timeIntervalSince(start) >= duration
            }()
            if opensNewBlock {
                if let start {
                    blocks.append(SessionBlock(start: start,
                                               end: start.addingTimeInterval(duration),
                                               totals: totals))
                }
                start = floorToHour(e.timestamp)
                totals = .zero
            }
            totals += e.totals
        }
        if let start {
            blocks.append(SessionBlock(start: start,
                                       end: start.addingTimeInterval(duration),
                                       totals: totals))
        }
        return blocks
    }

    /// The block containing `now`, if any. `nil` once the last block has closed —
    /// which *is* the window having reset, and means zero 5-hour usage.
    public static func current(_ blocks: [SessionBlock], now: Date) -> SessionBlock? {
        blocks.last { now >= $0.start && now < $0.end }
    }

    /// UTC hour floor — matches `aggregate`'s UTC month-boundary convention and
    /// keeps segmentation independent of the machine's timezone.
    static func floorToHour(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        // UTC is always resolvable by Foundation, so the force-unwrap is safe.
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    }
}
