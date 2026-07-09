import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

@Test func fiveHourIntervalIsLastFiveHours() {
    let i = TimeRange.fiveHour.interval(now: now)!
    #expect(i.start == now.addingTimeInterval(-5 * 3600))
    #expect(i.end == now)
}

@Test func last7And30DaysAreRolling() {
    #expect(TimeRange.last7Days.interval(now: now)!.start == now.addingTimeInterval(-7 * 86_400))
    #expect(TimeRange.last30Days.interval(now: now)!.start == now.addingTimeInterval(-30 * 86_400))
}

@Test func thisWeekStartsBeforeNowAndContainsIt() {
    let i = TimeRange.thisWeek.interval(now: now)!
    #expect(i.start <= now)
    #expect(i.contains(now))
    #expect(now.timeIntervalSince(i.start) < 7 * 86_400)  // within one week
}

@Test func allRangeHasNoInterval() {
    #expect(TimeRange.all.interval(now: now) == nil)
}

@Test func controlsHaveDisplayNames() {
    #expect(!DisplayUnit.tokens.displayName.isEmpty)
    #expect(!DisplayUnit.dollars.displayName.isEmpty)
    #expect(TimeRange.allCases.allSatisfy { !$0.displayName.isEmpty })
}

@Test func storageKeysRoundTrip() {
    for u in DisplayUnit.allCases { #expect(DisplayUnit(storageKey: u.storageKey) == u) }
    for r in TimeRange.allCases { #expect(TimeRange(storageKey: r.storageKey) == r) }
}

@Test func unknownStorageKeyFallsBackToDefault() {
    #expect(DisplayUnit(storageKey: nil) == .tokens)
    #expect(DisplayUnit(storageKey: "bogus") == .tokens)
    #expect(TimeRange(storageKey: nil) == .all)
    #expect(TimeRange(storageKey: "bogus") == .all)
}
