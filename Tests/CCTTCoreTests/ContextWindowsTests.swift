import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

@Test func ceilingDetectsOneMillionModels() {
    #expect(contextCeiling(model: "claude-opus-4-8[1m]") == 1_000_000)
    #expect(contextCeiling(model: "claude-opus-4-8") == 200_000)
    #expect(contextCeiling(model: "claude-sonnet-5") == 200_000)
}

@Test func contextSeriesIsOrderedAndSessionScoped() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-10), input: 100_000,
                           sessionId: "s1", requestId: "r2", messageId: "m2"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-100), input: 50_000,
                           sessionId: "s1", requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now, input: 20_000,
                           sessionId: "s2", requestId: "r3", messageId: "m3"),
    ]
    let pts = contextSeries(events: events, sessionId: "s1")
    #expect(pts.count == 2)
    #expect(pts.map(\.timestamp) == [now.addingTimeInterval(-100), now.addingTimeInterval(-10)])
    #expect(pts.first?.contextTokens == 50_000)
}

@Test func singleEventSessionHasNoCompaction() {
    let events = [UsageEvent.fixture(timestamp: now, input: 100_000, sessionId: "s1",
                                     requestId: "r1", messageId: "m1")]
    let pts = contextSeries(events: events, sessionId: "s1")
    #expect(pts.count == 1)
    #expect(pts[0].isCompaction == false)
}

@Test func sharpDropFlagsCompaction() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-100), input: 150_000,
                           sessionId: "s1", requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now, input: 20_000,
                           sessionId: "s1", requestId: "r2", messageId: "m2"),
    ]
    #expect(contextSeries(events: events, sessionId: "s1")[1].isCompaction == true)
}

@Test func gentleDeclineIsNotCompaction() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-100), input: 150_000,
                           sessionId: "s1", requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now, input: 120_000,
                           sessionId: "s1", requestId: "r2", messageId: "m2"),
    ]
    #expect(contextSeries(events: events, sessionId: "s1")[1].isCompaction == false)
}

@Test func contextSummaryComputesPeakAvgAndCompactions() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-100), model: "claude-opus-4-8",
                           input: 100_000, sessionId: "s1", requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now, model: "claude-opus-4-8",
                           input: 20_000, sessionId: "s1", requestId: "r2", messageId: "m2"),
    ]
    let sums = contextSummaries(events: events, range: .all, now: now)
    #expect(sums.count == 1)
    let s = sums[0]
    #expect(s.peakContext == 100_000)
    #expect(abs(s.avgContext - 60_000) < 1e-6)
    #expect(s.ceiling == 200_000)
    #expect(abs(s.peakPercentOfCeiling - 0.5) < 1e-6)
    #expect(s.compactionCount == 1)
}

@Test func contextSummariesRespectRange() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-60), input: 30_000,
                           sessionId: "in", requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-10 * 86_400), input: 30_000,
                           sessionId: "out", requestId: "r2", messageId: "m2"),
    ]
    let sums = contextSummaries(events: events, range: .fiveHour, now: now)
    #expect(sums.map(\.sessionId) == ["in"])
}
