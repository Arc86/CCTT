import Foundation
import Observation

/// Abstraction over the ingestor so the store can be tested with a stub.
public protocol UsageScanning: Sendable {
    func scan() -> ScanResult
}

/// Owns accumulated usage events and the published aggregated snapshot.
@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshot: UsageSnapshot

    private let scanner: UsageScanning
    private let clock: @Sendable () -> Date
    private var accumulated: [UsageEvent] = []
    private var totalParseErrors = 0

    public init(scanner: UsageScanning, clock: @escaping @Sendable () -> Date) {
        self.scanner = scanner
        self.clock = clock
        self.snapshot = .empty(now: clock())
    }

    /// Pull any new events from the scanner and re-publish the snapshot.
    public func refresh() {
        let result = scanner.scan()
        accumulated.append(contentsOf: result.events)
        totalParseErrors += result.parseErrors
        snapshot = aggregate(events: accumulated,
                             parseErrors: totalParseErrors,
                             now: clock())
    }

    /// On-demand costed breakdown of the retained events for a chosen time range.
    /// Raw events stay private (only the aggregated snapshot is published); the
    /// detail window pulls this when its range or the underlying data changes.
    public func breakdown(range: TimeRange, prices: PriceTable = .bundled) -> Breakdown {
        CCTTCore.breakdown(events: accumulated, range: range, now: clock(), prices: prices)
    }

    /// Spend-over-time series for the timeline chart (Plan 3B).
    public func timeline(range: TimeRange, prices: PriceTable = .bundled) -> [TimeBucket] {
        CCTTCore.timelineSeries(events: accumulated, range: range, now: clock(), prices: prices)
    }

    /// Ranked recent-session rows for the Sessions tab (Plan 3B).
    public func sessions(range: TimeRange, prices: PriceTable = .bundled) -> [SessionSummary] {
        CCTTCore.sessionSummaries(events: accumulated, range: range, now: clock(), prices: prices)
    }

    /// Per-session context statistics for the Context Windows tab (Plan 3B).
    public func contextSummaries(range: TimeRange) -> [ContextSessionSummary] {
        CCTTCore.contextSummaries(events: accumulated, range: range, now: clock())
    }

    /// The context-size series for one session (Plan 3B).
    public func contextSeries(sessionId: String) -> [ContextPoint] {
        CCTTCore.contextSeries(events: accumulated, sessionId: sessionId)
    }
}
