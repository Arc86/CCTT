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

    private enum CodingKeys: String, CodingKey {
        case byteOffset, inode, size, modTime
    }

    // Custom decoder so a cache JSON missing any key (e.g. one written before
    // `modTime` existed, or after a future schema change) still decodes with
    // sane defaults instead of throwing — which `OffsetCache.load`'s `try?`
    // would otherwise turn into a silent full-cache reset. Synthesized
    // `Decodable` ignores initializer defaults for absent keys, hence this.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        byteOffset = try c.decodeIfPresent(UInt64.self, forKey: .byteOffset) ?? 0
        inode = try c.decodeIfPresent(UInt64.self, forKey: .inode) ?? 0
        size = try c.decodeIfPresent(UInt64.self, forKey: .size) ?? 0
        modTime = try c.decodeIfPresent(TimeInterval.self, forKey: .modTime) ?? 0
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
