import Testing
import Foundation
@testable import CCTTCore

@Test func roundTripsThroughDisk() throws {
    var cache = OffsetCache()
    cache["/a/b.jsonl"] = FileState(byteOffset: 42, inode: 7, size: 42)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-\(UUID().uuidString).json")
    try cache.save(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let loaded = OffsetCache.load(from: url)
    #expect(loaded == cache)
    #expect(loaded["/a/b.jsonl"]?.byteOffset == 42)
}

@Test func loadReturnsEmptyWhenMissing() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-missing-\(UUID().uuidString).json")
    #expect(OffsetCache.load(from: url).files.isEmpty)
}

@Test func loadReturnsEmptyOnCorruptFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-corrupt-\(UUID().uuidString).json")
    try Data("{not json".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(OffsetCache.load(from: url).files.isEmpty)
}

@Test func loadToleratesMissingFieldsWithDefaults() throws {
    // Hand-written cache: one entry omits `modTime` (a pre-existing cache from
    // before that field was added), another omits a numeric field (`inode`).
    // Neither should fail decoding and silently reset the whole cache to empty.
    let json = """
    {"files":{
        "/a/b.jsonl":{"byteOffset":42,"inode":7,"size":42},
        "/c/d.jsonl":{"byteOffset":10,"size":10,"modTime":123.5}
    }}
    """
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-partial-\(UUID().uuidString).json")
    try Data(json.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let loaded = OffsetCache.load(from: url)
    #expect(loaded.files.count == 2)   // NOT reset to empty

    // Entry missing `modTime`: present fields survive, modTime defaults to 0.
    #expect(loaded["/a/b.jsonl"]?.byteOffset == 42)
    #expect(loaded["/a/b.jsonl"]?.inode == 7)
    #expect(loaded["/a/b.jsonl"]?.size == 42)
    #expect(loaded["/a/b.jsonl"]?.modTime == 0)

    // Entry missing `inode`: present fields survive, inode defaults to 0.
    #expect(loaded["/c/d.jsonl"]?.byteOffset == 10)
    #expect(loaded["/c/d.jsonl"]?.size == 10)
    #expect(loaded["/c/d.jsonl"]?.modTime == 123.5)
    #expect(loaded["/c/d.jsonl"]?.inode == 0)
}
