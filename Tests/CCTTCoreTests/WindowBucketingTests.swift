import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

@Test func bucketsFiveHourBlockAndRollingWeekly() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-3600),        // 1h ago
                           output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-3 * 86_400),  // 3d ago
                           output: 20, requestId: "r2", messageId: "m2"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-40 * 86_400), // 40d ago
                           output: 30, requestId: "r3", messageId: "m3"),
    ]
    let snap = aggregate(events: events, parseErrors: 0, now: now)
    // The 1h-ago event opens its own block (the 3d/40d-ago events are each far
    // enough apart to have aged out an earlier block); that block is still open
    // at `now`, so fiveHour counts only it — weekly stays a true rolling window.
    #expect(snap.fiveHour.output == 10)          // only the 1h-ago event's block
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

// MARK: - Anchored 5-hour block semantics

/// 2026-07-17T09:00:00Z — an exact UTC hour boundary.
private let blockHour0 = Date(timeIntervalSince1970: 1_784_278_800)

@Test func fiveHourCountsTheOpenBlockNotATrailingWindow() {
    let events = [
        UsageEvent.fixture(timestamp: blockHour0, output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: blockHour0.addingTimeInterval(2 * 3600),
                           output: 20, requestId: "r2", messageId: "m2"),
    ]
    // 12:00 — inside the 09:00–14:00 block. A trailing window would have dropped
    // the 09:00 event once it aged past 5h; the block keeps it until 14:00.
    let snap = aggregate(events: events, parseErrors: 0,
                         now: blockHour0.addingTimeInterval(3 * 3600))
    #expect(snap.fiveHour.output == 30)
    #expect(snap.fiveHourBlock?.start == blockHour0)
    #expect(snap.fiveHourBlock?.end == blockHour0.addingTimeInterval(5 * 3600))
}

@Test func fiveHourIsZeroOnceTheBlockHasClosed() {
    // The behaviour change: at 14:30 the 09:00 block has closed, so the window
    // has *reset* — it does not decay.
    let events = [
        UsageEvent.fixture(timestamp: blockHour0, output: 10, requestId: "r1", messageId: "m1")
    ]
    let snap = aggregate(events: events, parseErrors: 0,
                         now: blockHour0.addingTimeInterval(5 * 3600 + 1800))
    #expect(snap.fiveHour == .zero)
    #expect(snap.fiveHourBlock == nil)
}

@Test func emptySnapshotHasNoFiveHourBlock() {
    let snap = aggregate(events: [], parseErrors: 0, now: blockHour0)
    #expect(snap.fiveHourBlock == nil)
    #expect(snap.fiveHour == .zero)
}
