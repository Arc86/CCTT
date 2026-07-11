import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

@Test func ceilingReflectsModelContextWindow() {
    // 1M-context models. Claude Code strips the `[1m]` tag from the logged model
    // id, so the ceiling is derived from the model family, not that tag alone.
    #expect(contextCeiling(model: "claude-opus-4-8[1m]") == 1_000_000)
    #expect(contextCeiling(model: "claude-opus-4-8") == 1_000_000)
    #expect(contextCeiling(model: "claude-opus-4-7") == 1_000_000)
    #expect(contextCeiling(model: "claude-opus-4-6") == 1_000_000)
    #expect(contextCeiling(model: "claude-sonnet-4-6") == 1_000_000)
    #expect(contextCeiling(model: "claude-sonnet-5") == 1_000_000)
    #expect(contextCeiling(model: "claude-fable-5") == 1_000_000)
    #expect(contextCeiling(model: "sonnet") == 1_000_000)
    #expect(contextCeiling(model: "opus") == 1_000_000)

    // 200K-context models: Haiku, and older Opus/Sonnet generations.
    #expect(contextCeiling(model: "claude-haiku-4-5-20251001") == 200_000)
    #expect(contextCeiling(model: "haiku") == 200_000)
    #expect(contextCeiling(model: "claude-opus-4-5-20251101") == 200_000)
    #expect(contextCeiling(model: "claude-opus-4-1-20250805") == 200_000)
    #expect(contextCeiling(model: "claude-sonnet-4-5-20250929") == 200_000)
    #expect(contextCeiling(model: "claude-opus-4-20250514") == 200_000)
    #expect(contextCeiling(model: "<synthetic>") == 200_000)
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
    #expect(s.ceiling == 1_000_000)  // Opus 4.8 supports the 1M window
    #expect(abs(s.peakPercentOfCeiling - 0.1) < 1e-6)
    #expect(s.compactionCount == 1)
}

@Test func contextSummariesJoinTitlesBySessionId() {
    let events = [
        UsageEvent.fixture(timestamp: now, input: 10_000, sessionId: "s1",
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now, input: 10_000, sessionId: "s2",
                           requestId: "r2", messageId: "m2"),
    ]
    let sums = contextSummaries(events: events, range: .all, now: now,
                                titles: ["s1": "Context window work"])
    let byId = Dictionary(uniqueKeysWithValues: sums.map { ($0.sessionId, $0) })
    #expect(byId["s1"]?.title == "Context window work")
    #expect(byId["s2"]?.title == nil)
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
