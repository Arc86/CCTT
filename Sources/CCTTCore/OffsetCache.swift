import Foundation

/// Per-file read position so incremental scans parse only new bytes.
public struct FileState: Sendable, Equatable, Codable {
    public var byteOffset: UInt64   // bytes already consumed (points at a line boundary)
    public var inode: UInt64        // detects file rotation/replacement
    public var size: UInt64         // last-seen size; shrinkage => truncation
    // Last-seen mtime (seconds since epoch). Disambiguates an in-place rewrite
    // that happens to leave the file at the same size from a genuine no-op scan
    // (inode + size alone can't tell those apart).
    public var modTime: TimeInterval

    public init(byteOffset: UInt64, inode: UInt64, size: UInt64, modTime: TimeInterval = 0) {
        self.byteOffset = byteOffset; self.inode = inode; self.size = size
        self.modTime = modTime
    }
}

/// Maps absolute JSONL file path → last read position. Persisted as JSON.
public struct OffsetCache: Sendable, Equatable, Codable {
    public var files: [String: FileState]

    public init(files: [String: FileState] = [:]) { self.files = files }

    public subscript(path: String) -> FileState? {
        get { files[path] }
        set { files[path] = newValue }
    }

    /// Best-effort load; any error (missing, corrupt) yields an empty cache so
    /// the app self-heals by re-reading from scratch.
    public static func load(from url: URL) -> OffsetCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(OffsetCache.self, from: data)
        else { return OffsetCache() }
        return cache
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
