import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

@Test func timelineMergesEventsInSameSlot() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-100), output: 10,
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-200), output: 20,
                           requestId: "r2", messageId: "m2"),
    ]
    let series = timelineSeries(events: events, range: .fiveHour, now: now, prices: .bundled)
    let nonzero = series.filter { $0.totals.total > 0 }
    #expect(nonzero.count == 1)
    #expect(nonzero.first?.totals.output == 30)
}

@Test func timelineSeparatesDistantEventsWithZeroFill() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-1 * 86_400), output: 10,
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-20 * 86_400), output: 20,
                           requestId: "r2", messageId: "m2"),
    ]
    let series = timelineSeries(events: events, range: .last30Days, now: now, prices: .bundled)
    #expect(series.filter { $0.totals.total > 0 }.count == 2)
    #expect(series.count > 2)   // zero-filled slots between and around them
}

@Test func timelineAccruesCostAcrossSlots() {
    let events = [UsageEvent.fixture(timestamp: now.addingTimeInterval(-100),
                                     model: "claude-opus-4-8", input: 0, output: 1_000_000,
                                     requestId: "r1", messageId: "m1")]   // $25
    let series = timelineSeries(events: events, range: .fiveHour, now: now, prices: .bundled)
    #expect(series.count > 1)
    #expect(abs(series.reduce(0) { $0 + $1.costUSD } - 25) < 1e-6)
}

@Test func timelineExcludesOutOfRange() {
    let events = [UsageEvent.fixture(timestamp: now.addingTimeInterval(-10 * 86_400), output: 5,
                                     requestId: "r1", messageId: "m1")]
    let series = timelineSeries(events: events, range: .fiveHour, now: now, prices: .bundled)
    #expect(series.allSatisfy { $0.totals.total == 0 })
}

@Test func timelineEmptyWhenNoEventsAndAllRange() {
    #expect(timelineSeries(events: [], range: .all, now: now, prices: .bundled).isEmpty)
}
