import Foundation

/// The context-window ceiling (in tokens) for a model id: 1M for `[1m]` models,
/// otherwise the standard 200K.
public func contextCeiling(model: String) -> Int {
    model.contains("[1m]") ? 1_000_000 : 200_000
}

/// One point in a session's context-size-over-time series.
public struct ContextPoint: Sendable, Equatable {
    public let timestamp: Date
    public let contextTokens: Int   // input + cache-read + cache-creation for the message
    public let isCompaction: Bool   // sharp drop from the previous point (auto-compaction)
    public init(timestamp: Date, contextTokens: Int, isCompaction: Bool) {
        self.timestamp = timestamp; self.contextTokens = contextTokens
        self.isCompaction = isCompaction
    }
}

/// A message is treated as a compaction when context falls to ≤ half the previous
/// non-trivial value — the signature of Claude Code auto-compacting the window.
private let compactionRatio = 0.5
private let compactionFloor = 10_000

/// The chosen session's context-size series, ordered by time, with compaction
/// points flagged. Events are de-duplicated first.
public func contextSeries(events: [UsageEvent], sessionId: String) -> [ContextPoint] {
    let ordered = deduplicated(events)
        .filter { $0.sessionId == sessionId }
        .sorted { $0.timestamp < $1.timestamp }

    var points: [ContextPoint] = []
    points.reserveCapacity(ordered.count)
    var previous: Int? = nil
    for e in ordered {
        let ctx = e.totalContextTokens
        let compacted = previous.map { p in p >= compactionFloor && Double(ctx) <= compactionRatio * Double(p) } ?? false
        points.append(ContextPoint(timestamp: e.timestamp, contextTokens: ctx, isCompaction: compacted))
        previous = ctx
    }
    return points
}

/// Per-session context statistics for the Context Windows table.
public struct ContextSessionSummary: Sendable, Equatable {
    public let sessionId: String
    public let model: String
    public let ceiling: Int
    public let peakContext: Int
    public let avgContext: Double
    public let peakPercentOfCeiling: Double
    public let compactionCount: Int
    public init(sessionId: String, model: String, ceiling: Int, peakContext: Int,
                avgContext: Double, peakPercentOfCeiling: Double, compactionCount: Int) {
        self.sessionId = sessionId; self.model = model; self.ceiling = ceiling
        self.peakContext = peakContext; self.avgContext = avgContext
        self.peakPercentOfCeiling = peakPercentOfCeiling; self.compactionCount = compactionCount
    }
}

/// One summary per session active in `range`, sorted by peak context descending.
public func contextSummaries(events: [UsageEvent], range: TimeRange,
                             now: Date) -> [ContextSessionSummary] {
    let interval = range.interval(now: now)
    let inRange = deduplicated(events).filter { interval?.contains($0.timestamp) ?? true }
    let bySession = Dictionary(grouping: inRange, by: \.sessionId)

    return bySession.map { id, evs -> ContextSessionSummary in
        let series = contextSeries(events: evs, sessionId: id)
        let sizes = series.map(\.contextTokens)
        let peak = sizes.max() ?? 0
        let avg = sizes.isEmpty ? 0 : Double(sizes.reduce(0, +)) / Double(sizes.count)
        // Model of the session's latest event drives the ceiling.
        let model = evs.max { $0.timestamp < $1.timestamp }?.model ?? ""
        let ceiling = contextCeiling(model: model)
        return ContextSessionSummary(
            sessionId: id, model: model, ceiling: ceiling, peakContext: peak, avgContext: avg,
            peakPercentOfCeiling: ceiling > 0 ? Double(peak) / Double(ceiling) : 0,
            compactionCount: series.filter(\.isCompaction).count)
    }
    .sorted { $0.peakContext > $1.peakContext }
}
