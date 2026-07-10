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
    private let eventStore: EventStore?
    private let titleStore: SessionTitleStore?
    private var accumulated: [UsageEvent] = []
    /// `sessionId → title`, carried across restarts by `titleStore`. Joined into the
    /// session/context summaries so their lists show titles rather than raw IDs.
    private var sessionTitles: [String: String] = [:]
    private var totalParseErrors = 0

    /// Bumped only when `accumulated` actually changes, so the detail-window memos
    /// below serve cached results across tab switches / re-renders and recompute
    /// only when new events land. See `RangeMemo`.
    private var dataVersion = 0
    private let breakdownMemo = RangeMemo<Breakdown>()
    private let timelineMemo = RangeMemo<[TimeBucket]>()
    private let sessionsMemo = RangeMemo<[SessionSummary]>()
    private let hourlyMemo = RangeMemo<[HourBucket]>()
    private let contextMemo = RangeMemo<[ContextSessionSummary]>()

    /// One de-duplication pass per `dataVersion`, shared across every detail-window
    /// builder and range. `deduplicated` is range- and price-independent and is the
    /// dominant per-builder cost (~O(n) over all retained events), so computing it
    /// once — rather than inside each of the five builders on every tab switch —
    /// is the bulk of the detail window's speedup. Reset when `dataVersion` bumps.
    private var dedupedCache: (version: Int, events: [UsageEvent])?
    private func dedupedEvents() -> [UsageEvent] {
        if let c = dedupedCache, c.version == dataVersion { return c.events }
        let unique = deduplicated(accumulated)
        dedupedCache = (dataVersion, unique)
        return unique
    }

    /// - Parameters:
    ///   - eventStore: durable log that carries history across restarts. When
    ///     `nil` the store is purely in-memory (as in most unit tests).
    ///   - offsetCacheURL: the scanner's read-position cache. Supplied only so the
    ///     store can self-heal the one dangerous divergence: an event log that has
    ///     vanished while the offset cache still claims the source was read (which
    ///     would otherwise resurrect the history-loss bug). In that case the offset
    ///     cache — a rebuildable optimization — is reset so the next scan re-reads
    ///     all source. The durable event log is never reset here.
    public init(scanner: UsageScanning,
                eventStore: EventStore? = nil,
                titleStore: SessionTitleStore? = nil,
                offsetCacheURL: URL? = nil,
                clock: @escaping @Sendable () -> Date) {
        self.scanner = scanner
        self.clock = clock
        self.eventStore = eventStore
        self.titleStore = titleStore
        self.sessionTitles = titleStore?.load() ?? [:]

        let loaded = eventStore?.load() ?? []
        if loaded.isEmpty, let offsetCacheURL,
           !OffsetCache.load(from: offsetCacheURL).files.isEmpty {
            try? FileManager.default.removeItem(at: offsetCacheURL)
        }
        accumulated = loaded
        snapshot = loaded.isEmpty
            ? .empty(now: clock())
            : aggregate(events: loaded, parseErrors: 0, now: clock())
    }

    /// Pull any new events from the scanner, persist them, and re-publish the snapshot.
    public func refresh() {
        let result = scanner.scan()
        try? eventStore?.append(result.events)
        accumulated.append(contentsOf: result.events)
        totalParseErrors += result.parseErrors

        // Titles can update without new usage events (an `ai-title` line alone), so
        // track whether the map changed independently and invalidate the memos if so —
        // the session/context builders join `sessionTitles`.
        var titlesChanged = false
        for (sid, title) in result.titles where sessionTitles[sid] != title {
            sessionTitles[sid] = title
            titlesChanged = true
        }
        if titlesChanged { try? titleStore?.save(sessionTitles) }

        if !result.events.isEmpty || titlesChanged { dataVersion += 1 } // invalidate detail memos
        snapshot = aggregate(events: accumulated,
                             parseErrors: totalParseErrors,
                             now: clock())
    }

    /// On-demand costed breakdown of the retained events for a chosen time range.
    /// Raw events stay private (only the aggregated snapshot is published); the
    /// detail window pulls this when its range or the underlying data changes.
    /// The detail-window builders below all route through per-range memos keyed by
    /// `dataVersion`, so repeated calls at the same range (every tab switch and the
    /// 20-second re-render while idle) are O(1) dictionary hits instead of full
    /// re-scans of every retained event. The memos assume the app's single
    /// `.bundled` price table (its only caller); the value is captured in the
    /// closure so the first computation per range wins.
    public func breakdown(range: TimeRange, prices: PriceTable = .bundled) -> Breakdown {
        breakdownMemo.value(range: range, version: dataVersion) {
            CCTTCore.breakdown(deduped: dedupedEvents(), range: range, now: clock(), prices: prices)
        }
    }

    /// Spend-over-time series for the timeline chart (Plan 3B).
    public func timeline(range: TimeRange, prices: PriceTable = .bundled) -> [TimeBucket] {
        timelineMemo.value(range: range, version: dataVersion) {
            CCTTCore.timelineSeries(deduped: dedupedEvents(), range: range, now: clock(), prices: prices)
        }
    }

    /// Ranked recent-session rows for the Sessions tab (Plan 3B).
    public func sessions(range: TimeRange, prices: PriceTable = .bundled) -> [SessionSummary] {
        sessionsMemo.value(range: range, version: dataVersion) {
            CCTTCore.sessionSummaries(deduped: dedupedEvents(), range: range, now: clock(),
                                      prices: prices, titles: sessionTitles)
        }
    }

    /// Usage profiled by hour-of-day for the Sessions & Timeline tab.
    public func hourlyProfile(range: TimeRange,
                              timeZone: TimeZone = .current) -> [HourBucket] {
        hourlyMemo.value(range: range, version: dataVersion) {
            CCTTCore.hourlyProfile(deduped: dedupedEvents(), range: range, now: clock(),
                                   timeZone: timeZone)
        }
    }

    /// Per-session context statistics for the Context Windows tab (Plan 3B).
    public func contextSummaries(range: TimeRange) -> [ContextSessionSummary] {
        contextMemo.value(range: range, version: dataVersion) {
            CCTTCore.contextSummaries(deduped: dedupedEvents(), range: range, now: clock(),
                                      titles: sessionTitles)
        }
    }

    /// The context-size series for one session (Plan 3B). Reuses the shared dedup
    /// pass so selecting a session in the Context tab doesn't re-scan all events.
    public func contextSeries(sessionId: String) -> [ContextPoint] {
        CCTTCore.contextSeries(deduped: dedupedEvents(), sessionId: sessionId)
    }

    /// Total-token change for `range` versus the immediately preceding equal-length
    /// window, for the detail window's hero trend pill. `nil` when there's no honest
    /// comparison (`.all`, `.thisWeek`, or no previous-period baseline). Reuses the
    /// shared dedup pass; a single O(n) sum, so it isn't memoized.
    public func tokenDelta(range: TimeRange) -> Double? {
        CCTTCore.tokenDelta(deduped: dedupedEvents(), range: range, now: clock())
    }
}
