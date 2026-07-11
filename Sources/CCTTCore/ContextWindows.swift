import Foundation

/// The context-window ceiling (in tokens) for a model id.
///
/// Claude Code strips the `[1m]` beta tag from the `message.model` it logs, so the
/// ceiling can't be read off that tag alone — it's derived from the model family's
/// documented maximum context window. Opus 4.6+, Sonnet 4.6/5, and Fable/Mythos 5
/// ship the 1M window; Haiku and older Opus/Sonnet generations cap at 200K.
public func contextCeiling(model: String) -> Int {
    supportsMillionTokenContext(model) ? 1_000_000 : 200_000
}

/// Whether `model`'s family supports the 1M-token context window.
func supportsMillionTokenContext(_ model: String) -> Bool {
    let m = model.lowercased()

    // Explicit 1M beta tag (e.g. "claude-opus-4-8[1m]") is authoritative when present.
    if m.contains("[1m]") { return true }

    // Haiku and older Opus/Sonnet generations are 200K. Match these before the broad
    // family fallbacks so e.g. "opus-4-5" isn't caught by the bare-"opus" alias.
    if m.contains("haiku") { return false }
    let only200K = ["opus-4-5", "opus-4-1", "opus-4-0", "opus-4-2025",
                    "3-opus", "sonnet-4-5", "sonnet-4-0", "sonnet-4-2025",
                    "3-7-sonnet", "3-5-sonnet", "3-sonnet"]
    if only200K.contains(where: m.contains) { return false }

    // Model families whose current members all ship the 1M window.
    let million = ["opus-4-6", "opus-4-7", "opus-4-8",
                   "sonnet-4-6", "sonnet-5", "fable-5", "mythos"]
    if million.contains(where: m.contains) { return true }

    // Bare aliases resolve to the latest model, which is 1M for opus/sonnet.
    if m == "opus" || m == "sonnet" { return true }

    return false
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
    contextSeries(deduped: deduplicated(events), sessionId: sessionId)
}

/// As `contextSeries(events:…)` but for already-`deduplicated` events.
public func contextSeries(deduped events: [UsageEvent], sessionId: String) -> [ContextPoint] {
    let ordered = events
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
public struct ContextSessionSummary: Sendable, Equatable, Identifiable {
    public var id: String { sessionId }
    public let sessionId: String
    /// Claude Code's generated title for the session, when known; `nil` falls back to
    /// the session ID in the UI.
    public let title: String?
    public let model: String
    public let ceiling: Int
    public let peakContext: Int
    public let avgContext: Double
    public let peakPercentOfCeiling: Double
    public let compactionCount: Int
    public init(sessionId: String, title: String? = nil, model: String, ceiling: Int,
                peakContext: Int, avgContext: Double, peakPercentOfCeiling: Double,
                compactionCount: Int) {
        self.sessionId = sessionId; self.title = title; self.model = model; self.ceiling = ceiling
        self.peakContext = peakContext; self.avgContext = avgContext
        self.peakPercentOfCeiling = peakPercentOfCeiling; self.compactionCount = compactionCount
    }
}

/// One summary per session active in `range`, sorted by peak context descending.
/// `titles` maps `sessionId → title` (from Claude Code `ai-title` lines).
public func contextSummaries(events: [UsageEvent], range: TimeRange, now: Date,
                             titles: [String: String] = [:]) -> [ContextSessionSummary] {
    contextSummaries(deduped: deduplicated(events), range: range, now: now, titles: titles)
}

/// As `contextSummaries(events:…)` but for already-`deduplicated` events, so the
/// detail window can share a single dedup pass across all its builders.
public func contextSummaries(deduped events: [UsageEvent], range: TimeRange, now: Date,
                             titles: [String: String] = [:]) -> [ContextSessionSummary] {
    let interval = range.interval(now: now)
    let inRange = events.filter { interval?.contains($0.timestamp) ?? true }
    let bySession = Dictionary(grouping: inRange, by: \.sessionId)

    return bySession.map { id, evs -> ContextSessionSummary in
        let series = contextSeries(deduped: evs, sessionId: id)
        let sizes = series.map(\.contextTokens)
        let peak = sizes.max() ?? 0
        let avg = sizes.isEmpty ? 0 : Double(sizes.reduce(0, +)) / Double(sizes.count)
        // Model of the session's latest event drives the ceiling.
        let model = evs.max { $0.timestamp < $1.timestamp }?.model ?? ""
        let ceiling = contextCeiling(model: model)
        return ContextSessionSummary(
            sessionId: id, title: titles[id], model: model, ceiling: ceiling, peakContext: peak,
            avgContext: avg,
            peakPercentOfCeiling: ceiling > 0 ? Double(peak) / Double(ceiling) : 0,
            compactionCount: series.filter(\.isCompaction).count)
    }
    .sorted { $0.peakContext > $1.peakContext }
}
