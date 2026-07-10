import Testing
import Foundation
@testable import CCTTCore

private final class StubScanner: UsageScanning, @unchecked Sendable {
    var queued: [ScanResult] = []
    func scan() -> ScanResult {
        queued.isEmpty ? ScanResult(events: [], parseErrors: 0) : queued.removeFirst()
    }
}

@MainActor
@Test func refreshAccumulatesAcrossScans() {
    let scanner = StubScanner()
    scanner.queued = [
        ScanResult(events: [UsageEvent.fixture(output: 10, requestId: "r1", messageId: "m1")],
                   parseErrors: 0),
        ScanResult(events: [UsageEvent.fixture(output: 20, requestId: "r2", messageId: "m2")],
                   parseErrors: 1),
    ]
    let store = UsageStore(scanner: scanner,
                           clock: { Date(timeIntervalSince1970: 1_783_000_000) })
    store.refresh()
    #expect(store.snapshot.overall.output == 10)
    store.refresh()
    #expect(store.snapshot.overall.output == 30)      // accumulated
    #expect(store.snapshot.overall.eventCount == 2)
    #expect(store.snapshot.parseErrors == 1)          // accumulated error count
}

@MainActor
@Test func breakdownReflectsAccumulatedEvents() {
    let now = Date(timeIntervalSince1970: 1_783_000_000)
    let scanner = StubScanner()
    scanner.queued = [ScanResult(events: [
        UsageEvent.fixture(timestamp: now, output: 10, project: "P",
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now, output: 10, project: "P",   // duplicate ids
                           requestId: "r1", messageId: "m1"),
    ], parseErrors: 0)]
    let store = UsageStore(scanner: scanner, clock: { now })
    store.refresh()
    let b = store.breakdown(range: .all)
    #expect(b.byProject.first?.key == "P")
    #expect(b.totals.eventCount == 1)   // deduped
}

@MainActor
@Test func memoizedBreakdownInvalidatesWhenNewEventsArrive() {
    let now = Date(timeIntervalSince1970: 1_783_000_000)
    let scanner = StubScanner()
    scanner.queued = [
        ScanResult(events: [UsageEvent.fixture(timestamp: now, output: 10, project: "P",
                                               requestId: "r1", messageId: "m1")], parseErrors: 0),
        ScanResult(events: [], parseErrors: 0),                       // no new events
        ScanResult(events: [UsageEvent.fixture(timestamp: now, output: 5, project: "P",
                                               requestId: "r2", messageId: "m2")], parseErrors: 0),
    ]
    let store = UsageStore(scanner: scanner, clock: { now })

    store.refresh()
    #expect(store.breakdown(range: .all).totals.output == 10)        // computed + cached
    store.refresh()                                                  // empty scan → cache holds
    #expect(store.breakdown(range: .all).totals.output == 10)
    store.refresh()                                                  // new event → memo invalidated
    #expect(store.breakdown(range: .all).totals.output == 15)        // not stale
}

@MainActor
@Test func startsEmpty() {
    let store = UsageStore(scanner: StubScanner(),
                           clock: { Date(timeIntervalSince1970: 0) })
    #expect(store.snapshot.overall.eventCount == 0)
}

@MainActor
@Test func historySurvivesRestartViaEventStore() {
    let now = Date(timeIntervalSince1970: 1_783_000_000)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-restart-\(UUID().uuidString)/events.jsonl")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let eventStore = EventStore(url: url)

    // First launch: a scan yields one event, persisted to the log.
    let scanner1 = StubScanner()
    scanner1.queued = [ScanResult(events: [UsageEvent.fixture(
        timestamp: now, output: 42, requestId: "r1", messageId: "m1")], parseErrors: 0)]
    let s1 = UsageStore(scanner: scanner1, eventStore: eventStore, clock: { now })
    s1.refresh()
    #expect(s1.snapshot.overall.output == 42)

    // Relaunch: fresh store, scanner returns nothing new (offsets would have
    // advanced). History must still be present, published at init.
    let s2 = UsageStore(scanner: StubScanner(), eventStore: eventStore, clock: { now })
    #expect(s2.snapshot.overall.output == 42)      // loaded from the log, no refresh needed
    #expect(s2.snapshot.overall.eventCount == 1)
}

@MainActor
@Test func titlesFromScanReachSessionAndContextSummaries() {
    let now = Date(timeIntervalSince1970: 1_783_000_000)
    let scanner = StubScanner()
    scanner.queued = [ScanResult(
        events: [UsageEvent.fixture(timestamp: now, output: 10, sessionId: "s1",
                                    requestId: "r1", messageId: "m1")],
        parseErrors: 0,
        titles: ["s1": "Session one"])]
    let store = UsageStore(scanner: scanner, clock: { now })
    store.refresh()
    #expect(store.sessions(range: .all).first?.title == "Session one")
    #expect(store.contextSummaries(range: .all).first?.title == "Session one")
}

@MainActor
@Test func titleOnlyScanRefreshesSummaries() {
    let now = Date(timeIntervalSince1970: 1_783_000_000)
    let scanner = StubScanner()
    scanner.queued = [
        ScanResult(events: [UsageEvent.fixture(timestamp: now, output: 10, sessionId: "s1",
                                               requestId: "r1", messageId: "m1")], parseErrors: 0),
        ScanResult(events: [], parseErrors: 0, titles: ["s1": "Arrived late"]),  // no new events
    ]
    let store = UsageStore(scanner: scanner, clock: { now })
    store.refresh()
    #expect(store.sessions(range: .all).first?.title == nil)   // computed + memoized
    store.refresh()                                            // title-only scan must invalidate
    #expect(store.sessions(range: .all).first?.title == "Arrived late")
}

@MainActor
@Test func titlesSurviveRestartViaTitleStore() {
    let now = Date(timeIntervalSince1970: 1_783_000_000)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-title-restart-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let eventStore = EventStore(url: dir.appendingPathComponent("events.jsonl"))
    let titleStore = SessionTitleStore(url: dir.appendingPathComponent("session-titles.json"))

    let scanner1 = StubScanner()
    scanner1.queued = [ScanResult(
        events: [UsageEvent.fixture(timestamp: now, output: 10, sessionId: "s1",
                                    requestId: "r1", messageId: "m1")],
        parseErrors: 0, titles: ["s1": "Persisted title"])]
    let s1 = UsageStore(scanner: scanner1, eventStore: eventStore, titleStore: titleStore, clock: { now })
    s1.refresh()
    #expect(s1.sessions(range: .all).first?.title == "Persisted title")

    // Relaunch: fresh store, scanner returns nothing new. The title must still be present.
    let s2 = UsageStore(scanner: StubScanner(), eventStore: eventStore,
                        titleStore: titleStore, clock: { now })
    #expect(s2.sessions(range: .all).first?.title == "Persisted title")
}

@MainActor
@Test func resetsOffsetCacheWhenEventLogVanishedButOffsetsRemain() throws {
    // The exact shape of the history-loss bug's corrupt-recovery case: the offset
    // cache says "already read the source" but the durable event log is gone.
    // The store must reset the (rebuildable) offset cache so the next scan re-reads
    // all source and repopulates the log — never silently keep skipping.
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-diverge-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let offsetURL = dir.appendingPathComponent("offsets.json")
    let eventURL = dir.appendingPathComponent("events.jsonl")   // intentionally absent

    var cache = OffsetCache()
    cache["/some/session.jsonl"] = FileState(byteOffset: 1024, inode: 9, size: 1024)
    try cache.save(to: offsetURL)
    #expect(FileManager.default.fileExists(atPath: offsetURL.path))

    _ = UsageStore(scanner: StubScanner(), eventStore: EventStore(url: eventURL),
                   offsetCacheURL: offsetURL, clock: { Date(timeIntervalSince1970: 0) })

    #expect(!FileManager.default.fileExists(atPath: offsetURL.path))  // reset → full re-scan
}
