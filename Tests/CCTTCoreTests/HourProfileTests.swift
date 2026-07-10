import Testing
import Foundation
@testable import CCTTCore

private let utc = TimeZone(identifier: "UTC")!

private func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
    return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
}

@Test func hourlyProfileAlwaysHas24Buckets() {
    let p = hourlyProfile(events: [], range: .all, now: utcDate(2026, 7, 9, 12), timeZone: utc)
    #expect(p.count == 24)
    #expect(p.map(\.hour) == Array(0..<24))
    #expect(p.allSatisfy { $0.totals.total == 0 })
}

@Test func hourlyProfileBucketsByLocalHour() {
    let events = [
        UsageEvent.fixture(timestamp: utcDate(2026, 7, 1, 9), output: 10,
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: utcDate(2026, 7, 2, 9), output: 20,
                           requestId: "r2", messageId: "m2"),   // same hour, next day
        UsageEvent.fixture(timestamp: utcDate(2026, 7, 1, 14), output: 5,
                           requestId: "r3", messageId: "m3"),
    ]
    let p = hourlyProfile(events: events, range: .all,
                          now: utcDate(2026, 7, 9, 12), timeZone: utc)
    #expect(p[9].totals.output == 30)
    #expect(p[9].activeDays == 2)                 // two distinct days at hour 9
    // Fixture default input is 100 each → hour-9 total = 200 input + 30 output = 230.
    #expect(p[9].totals.total == 230)
    #expect(p[9].averageTokensPerActiveDay == 115)
    #expect(p[14].totals.output == 5)
    #expect(p[14].activeDays == 1)
    #expect(p[0].totals.total == 0)
}

@Test func hourlyProfileMarksThrottleWindowInItsTimeZone() {
    // With the profile rendered in Pacific time, Anthropic's 05:00–11:00 PT band
    // maps directly onto local hours 5...10.
    let pt = TimeZone(identifier: "America/Los_Angeles")!
    let p = hourlyProfile(events: [], range: .all,
                          now: utcDate(2026, 7, 9, 12), timeZone: pt)
    for h in 0..<24 {
        #expect(p[h].inThrottleWindow == (5...10).contains(h))
    }
}

@Test func hourlyProfileRespectsRange() {
    let now = utcDate(2026, 7, 9, 12)
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-3600), output: 10,   // in 5h
                           requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-10 * 86_400), output: 99, // out
                           requestId: "r2", messageId: "m2"),
    ]
    let p = hourlyProfile(events: events, range: .fiveHour, now: now, timeZone: utc)
    #expect(p.reduce(0) { $0 + $1.totals.output } == 10)
}
