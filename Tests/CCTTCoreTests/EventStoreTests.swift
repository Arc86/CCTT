import Testing
import Foundation
@testable import CCTTCore

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-events-\(UUID().uuidString)/events.jsonl")
}

@Test func eventStoreRoundTripsThroughDisk() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = EventStore(url: url)

    let events = [
        UsageEvent.fixture(output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(output: 20, requestId: "r2", messageId: "m2"),
    ]
    try store.append(events)

    let loaded = store.load()
    #expect(loaded == events)
}

@Test func eventStoreLoadReturnsEmptyWhenMissing() {
    #expect(EventStore(url: tempURL()).load().isEmpty)
}

@Test func eventStoreAppendAccumulatesAcrossCalls() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = EventStore(url: url)

    try store.append([UsageEvent.fixture(output: 10, requestId: "r1", messageId: "m1")])
    try store.append([UsageEvent.fixture(output: 20, requestId: "r2", messageId: "m2")])

    let loaded = store.load()
    #expect(loaded.count == 2)
    #expect(loaded.map(\.outputTokens) == [10, 20])
}

@Test func eventStoreSkipsCorruptLinesButKeepsTheRest() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = EventStore(url: url)
    try store.append([UsageEvent.fixture(output: 10, requestId: "r1", messageId: "m1")])

    // Simulate a torn/garbage line (e.g. a crash mid-append) followed by a good one.
    let good = try JSONEncoder().encode(
        UsageEvent.fixture(output: 30, requestId: "r3", messageId: "m3"))
    var blob = Data("{ not json\n".utf8)
    blob.append(good); blob.append(0x0A)
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd(); try handle.write(contentsOf: blob); try handle.close()

    let loaded = store.load()
    #expect(loaded.map(\.outputTokens) == [10, 30])   // corrupt middle line skipped
}

@Test func eventStoreAppendEmptyIsNoOp() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = EventStore(url: url)
    try store.append([])
    #expect(store.load().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}
