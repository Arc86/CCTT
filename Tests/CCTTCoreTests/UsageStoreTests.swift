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
@Test func startsEmpty() {
    let store = UsageStore(scanner: StubScanner(),
                           clock: { Date(timeIntervalSince1970: 0) })
    #expect(store.snapshot.overall.eventCount == 0)
}
