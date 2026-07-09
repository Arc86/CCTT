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

@Test func unknownModelContributesZeroCostButCountsTokens() {
    let events = [UsageEvent.fixture(timestamp: now, model: "gpt-4", input: 0, output: 100,
                                     requestId: "r1", messageId: "m1")]
    let b = breakdown(events: events, range: .all, now: now, prices: .bundled)
    #expect(b.totalCostUSD == 0)
    #expect(b.totals.output == 100)
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
