import Foundation

/// Durable `sessionId → title` map (from Claude Code `ai-title` lines).
///
/// Why this exists: the ingest is incremental (a byte-offset cache means old bytes are
/// never re-read), so a session's `ai-title` line is seen only once — on the scan that
/// first read it. `EventStore` already persists parsed usage across restarts for exactly
/// this reason; titles need the same treatment, or the Sessions/Context lists would fall
/// back to raw session IDs after every relaunch until each session next emits a title.
///
/// Unlike `EventStore`'s append-only log, this is one entry per session (bounded, and only
/// the latest title matters), so it's a single small JSON dict rewritten atomically.
public struct SessionTitleStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// Best-effort load. Missing or corrupt file → `[:]` (never throws).
    public func load() -> [String: String] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let titles = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return titles
    }

    /// Atomically write the whole map, creating the directory if needed. Empty input
    /// still writes (an emptied map is a legitimate state to persist).
    public func save(_ titles: [String: String]) throws {
        let blob = try JSONEncoder().encode(titles)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try blob.write(to: url, options: .atomic)
    }
}
