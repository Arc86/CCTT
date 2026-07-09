import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

@Test func bucketsRollingFiveHourAndWeekly() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-3600),        // 1h ago
                           output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-3 * 86_400),  // 3d ago
                           output: 20, requestId: "r2", messageId: "m2"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-40 * 86_400), // 40d ago
                           output: 30, requestId: "r3", messageId: "m3"),
    ]
    let snap = aggregate(events: events, parseErrors: 0, now: now)
    #expect(snap.fiveHour.output == 10)          // only the 1h-ago event
    #expect(snap.weekly.output == 30)            // 1h + 3d
    #expect(snap.overall.output == 60)           // all three
}

@Test func bucketsMonthToDateWithByModel() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
    let events = [
        UsageEvent.fixture(timestamp: monthStart.addingTimeInterval(3600),
                           model: "claude-opus-4-8", output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: monthStart.addingTimeInterval(-3600),
                           model: "claude-opus-4-8", output: 20, requestId: "r2", messageId: "m2"),
    ]
    let snap = aggregate(events: events, parseErrors: 0, now: now)
    #expect(snap.monthToDate.output == 10)       // only the in-month event
    #expect(snap.monthByModel.count == 1)
    #expect(snap.monthByModel.first?.key == "claude-opus-4-8")
    #expect(snap.monthByModel.first?.totals.output == 10)
}

@Test func emptySnapshotHasZeroWindows() {
    let snap = aggregate(events: [], parseErrors: 0, now: now)
    #expect(snap.fiveHour == .zero)
    #expect(snap.weekly == .zero)
    #expect(snap.monthToDate == .zero)
    #expect(snap.monthByModel.isEmpty)
}
