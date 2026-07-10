import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

@Test func breakdownFiltersToRange() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-3600), project: "A",
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-10 * 86_400), project: "B",
                           requestId: "r2", messageId: "m2"),
    ]
    let b = breakdown(events: events, range: .fiveHour, now: now, prices: .bundled)
    #expect(b.byProject.count == 1)
    #expect(b.byProject.first?.key == "A")
}

@Test func projectCostSumsAcrossItsModels() {
    let events = [
        UsageEvent.fixture(timestamp: now, model: "claude-opus-4-8", input: 0, output: 1_000_000,
                           project: "P", requestId: "r1", messageId: "m1"),   // $25
        UsageEvent.fixture(timestamp: now, model: "claude-haiku-4-5", input: 0, output: 1_000_000,
                           project: "P", requestId: "r2", messageId: "m2"),    // $5
    ]
    let b = breakdown(events: events, range: .all, now: now, prices: .bundled)
    #expect(b.byProject.count == 1)
    #expect(abs(b.byProject.first!.costUSD - 30) < 1e-6)
    #expect(b.byModel.count == 2)
    #expect(abs(b.totalCostUSD - 30) < 1e-6)
}

@Test func unknownModelIsUnpricedNotZeroCost() {
    let events = [UsageEvent.fixture(timestamp: now, model: "gpt-4", input: 0, output: 100,
                                     requestId: "r1", messageId: "m1")]
    let b = breakdown(events: events, range: .all, now: now, prices: .bundled)
    #expect(b.totalCostUSD == 0)
    #expect(b.totals.output == 100)
    // The tokens are flagged unpriced so the UI shows "n/a", not a false "$0".
    #expect(b.unpricedTokens == 100)
    #expect(b.costUnavailable)
    #expect(b.byModel.first?.costUnavailable == true)
}

@Test func mixedPricedAndUnpricedFlagsPartialTotal() {
    let events = [
        UsageEvent.fixture(timestamp: now, model: "claude-opus-4-8", input: 0, output: 1_000_000,
                           project: "P", requestId: "r1", messageId: "m1"),   // $25, priced
        UsageEvent.fixture(timestamp: now, model: "gpt-4", input: 0, output: 100,
                           project: "P", requestId: "r2", messageId: "m2"),    // unpriced
    ]
    let b = breakdown(events: events, range: .all, now: now, prices: .bundled)
    #expect(abs(b.totalCostUSD - 25) < 1e-6)   // priced portion only
    #expect(b.unpricedTokens == 100)
    #expect(b.costPartial)
    #expect(!b.costUnavailable)
    // The mixed project row is not "n/a" (it has priced tokens) but carries unpriced.
    #expect(b.byProject.first?.costUnavailable == false)
    #expect(b.byProject.first?.unpricedTokens == 100)
}

@Test func breaksDownByGitBranchExcludingEventsWithoutOne() {
    let events = [
        UsageEvent.fixture(timestamp: now, output: 30, requestId: "r1", messageId: "m1",
                           gitBranch: "main"),
        UsageEvent.fixture(timestamp: now, output: 70, requestId: "r2", messageId: "m2",
                           gitBranch: "feature-x"),
        UsageEvent.fixture(timestamp: now, output: 10, requestId: "r3", messageId: "m3",
                           gitBranch: nil),   // excluded from byBranch
    ]
    let b = breakdown(events: events, range: .all, now: now, prices: .bundled)
    #expect(b.byBranch.map(\.key) == ["feature-x", "main"])   // sorted by tokens desc
    #expect(b.byBranch.first?.totals.output == 70)
    #expect(b.turnCount == 3)          // all turns still counted overall
    #expect(b.sessionCount == 1)       // one session across the fixtures
}

@Test func emptyEventsGiveEmptyBreakdown() {
    #expect(breakdown(events: [], range: .all, now: now, prices: .bundled) == Breakdown.empty)
}

@Test func breakdownDeduplicatesRepeatedIds() {
    let e = UsageEvent.fixture(timestamp: now, output: 50, requestId: "r1", messageId: "m1")
    let b = breakdown(events: [e, e], range: .all, now: now, prices: .bundled)
    #expect(b.totals.eventCount == 1)
}

@Test func dimensionsSortByTokensDescending() {
    let events = [
        UsageEvent.fixture(timestamp: now, output: 10, project: "small",
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now, output: 100, project: "big",
                           requestId: "r2", messageId: "m2"),
    ]
    let b = breakdown(events: events, range: .all, now: now, prices: .bundled)
    #expect(b.byProject.map(\.key) == ["big", "small"])
}

@Test func sessionAgentSkillPluginDimensionsPopulated() {
    let events = [
        UsageEvent.fixture(timestamp: now, sessionId: "s1", isSidechain: false,
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now, sessionId: "s2", isSidechain: true,
                           skill: "brainstorm", plugin: "superpowers",
                           requestId: "r2", messageId: "m2"),
    ]
    let b = breakdown(events: events, range: .all, now: now, prices: .bundled)
    #expect(Set(b.bySession.map(\.key)) == ["s1", "s2"])
    #expect(Set(b.byAgentKind.map(\.key)) == ["main", "subagent"])
    #expect(b.bySkill.map(\.key) == ["brainstorm"])
    #expect(b.byPlugin.map(\.key) == ["superpowers"])
}
