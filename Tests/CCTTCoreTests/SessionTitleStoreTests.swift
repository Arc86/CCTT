import Testing
import Foundation
@testable import CCTTCore

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-titles-\(UUID().uuidString)/session-titles.json")
}

@Test func savesAndLoadsRoundTrip() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = SessionTitleStore(url: url)
    try store.save(["s1": "First", "s2": "Second"])
    #expect(store.load() == ["s1": "First", "s2": "Second"])
}

@Test func missingFileLoadsEmpty() {
    let store = SessionTitleStore(url: tempURL())
    #expect(store.load().isEmpty)
}

@Test func corruptFileLoadsEmpty() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{ not json".utf8).write(to: url)
    #expect(SessionTitleStore(url: url).load().isEmpty)
}
