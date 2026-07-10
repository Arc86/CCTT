import Foundation

/// Durable, append-only log of parsed `UsageEvent`s (newline-delimited JSON, one
/// event per line — the same shape as the source files).
///
/// Why this exists: the offset cache persists each source file's read position
/// across launches, but the parsed events themselves used to live only in memory.
/// So after a restart a scan returned only events written *since the last run*,
/// and all prior history — the 5h/weekly windows, all-time totals, every
/// breakdown — silently reset to near-zero. Loading this log at startup restores
/// that history; the offset cache remains a rebuildable read-position optimization.
///
/// Append-only JSONL (not a rewritten JSON array) keeps writes cheap and makes a
/// torn trailing line from a crash harmless — `load` decodes each line
/// independently and skips any that fail, so one bad line never discards history.
public struct EventStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// Best-effort load. Missing file → `[]`. Each line is decoded on its own so a
    /// single corrupt/torn line is skipped rather than dropping the whole log.
    public func load() -> [UsageEvent] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        var events: [UsageEvent] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let event = try? decoder.decode(UsageEvent.self, from: Data(line)) {
                events.append(event)
            }
        }
        return events
    }

    /// Append events as JSON lines, creating the file (and its directory) if
    /// needed. Empty input is a no-op (never creates an empty file).
    public func append(_ events: [UsageEvent]) throws {
        guard !events.isEmpty else { return }
        let encoder = JSONEncoder()
        var blob = Data()
        for event in events {
            blob.append(try encoder.encode(event))
            blob.append(0x0A)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: blob)
        } else {
            try blob.write(to: url, options: .atomic)   // file didn't exist yet
        }
    }
}
