import Testing
import Foundation
@testable import CCTTCore

private let fixedNow = Date(timeIntervalSince1970: 1_783_000_000)

@Test func aggregatesOverallTotals() {
    let events = [
        UsageEvent.fixture(input: 100, output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(input: 200, output: 20, requestId: "r2", messageId: "m2"),
    ]
    let snap = aggregate(events: events, parseErrors: 0, now: fixedNow)
    #expect(snap.overall.input == 300)
    #expect(snap.overall.output == 30)
    #expect(snap.overall.eventCount == 2)
    #expect(snap.generatedAt == fixedNow)
}

@Test func dedupsOnRequestAndMessageId() {
    let events = [
        UsageEvent.fixture(output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(output: 10, requestId: "r1", messageId: "m1"), // dup
        UsageEvent.fixture(output: 20, requestId: "r2", messageId: "m2"),
    ]
    let snap = aggregate(events: events, parseErrors: 0, now: fixedNow)
    #expect(snap.overall.eventCount == 2)
    #expect(snap.overall.output == 30)
}

@Test func nilKeyEventsAreAlwaysCounted() {
    let events = [
        UsageEvent.fixture(output: 10, requestId: nil, messageId: nil),
        UsageEvent.fixture(output: 10, requestId: nil, messageId: nil),
    ]
    let snap = aggregate(events: events, parseErrors: 0, now: fixedNow)
    #expect(snap.overall.eventCount == 2)
}

@Test func groupsByProjectSortedDescending() {
    let events = [
        UsageEvent.fixture(output: 10, project: "small", requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(output: 500, project: "big", requestId: "r2", messageId: "m2"),
        UsageEvent.fixture(output: 40, project: "small", requestId: "r3", messageId: "m3"),
    ]
    let snap = aggregate(events: events, parseErrors: 0, now: fixedNow)
    #expect(snap.byProject.map(\.key) == ["big", "small"])
    #expect(snap.byProject.first?.totals.output == 500)
    #expect(snap.byProject.last?.totals.output == 50)
}

@Test func groupsByAgentKind() {
    let events = [
        UsageEvent.fixture(output: 10, isSidechain: false, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(output: 20, isSidechain: true, requestId: "r2", messageId: "m2"),
    ]
    let snap = aggregate(events: events, parseErrors: 0, now: fixedNow)
    let kinds = Dictionary(uniqueKeysWithValues: snap.byAgentKind.map { ($0.key, $0.totals.output) })
    #expect(kinds["main"] == 10)
    #expect(kinds["subagent"] == 20)
}

@Test func skillAndPluginRollupsExcludeNil() {
    let events = [
        UsageEvent.fixture(output: 10, skill: "brainstorming", plugin: "superpowers",
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(output: 20, skill: nil, plugin: nil,
                           requestId: "r2", messageId: "m2"),
    ]
    let snap = aggregate(events: events, parseErrors: 0, now: fixedNow)
    #expect(snap.bySkill.count == 1)
    #expect(snap.bySkill.first?.key == "brainstorming")
    #expect(snap.byPlugin.count == 1)
    #expect(snap.byPlugin.first?.key == "superpowers")
}

@Test func carriesParseErrors() {
    let snap = aggregate(events: [], parseErrors: 3, now: fixedNow)
    #expect(snap.parseErrors == 3)
    #expect(snap.overall.eventCount == 0)
}
