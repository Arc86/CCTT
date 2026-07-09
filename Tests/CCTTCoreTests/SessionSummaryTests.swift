import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

@Test func sessionSummaryAggregatesAndBoundsActivity() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-3600), output: 10,
                           sessionId: "s1", project: "P", requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-60), output: 20,
                           sessionId: "s1", project: "P", requestId: "r2", messageId: "m2"),
    ]
    let sums = sessionSummaries(events: events, range: .all, now: now, prices: .bundled)
    #expect(sums.count == 1)
    let s = sums[0]
    #expect(s.sessionId == "s1")
    #expect(s.totals.output == 30)
    #expect(s.firstActivity == now.addingTimeInterval(-3600))
    #expect(s.lastActivity == now.addingTimeInterval(-60))
}

@Test func sessionSummariesSortByMostRecentFirst() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-10_000), sessionId: "old",
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-10), sessionId: "new",
                           requestId: "r2", messageId: "m2"),
    ]
    let sums = sessionSummaries(events: events, range: .all, now: now, prices: .bundled)
    #expect(sums.map(\.sessionId) == ["new", "old"])
}

@Test func sessionSummariesRespectRange() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-60), sessionId: "in",
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-10 * 86_400), sessionId: "out",
                           requestId: "r2", messageId: "m2"),
    ]
    let sums = sessionSummaries(events: events, range: .fiveHour, now: now, prices: .bundled)
    #expect(sums.map(\.sessionId) == ["in"])
}
