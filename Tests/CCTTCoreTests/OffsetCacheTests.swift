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
