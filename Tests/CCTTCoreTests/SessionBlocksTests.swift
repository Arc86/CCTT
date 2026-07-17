import Testing
import Foundation
@testable import CCTTCore

/// 2026-07-17T09:00:00Z — an exact UTC hour boundary, so flooring is unambiguous.
private let hour0 = Date(timeIntervalSince1970: 1_784_278_800)
private let fiveHours: TimeInterval = 5 * 3600

@Test func emptyInputYieldsNoBlocks() {
    #expect(SessionBlocks.segment([]).isEmpty)
}

@Test func singleEventOpensOneBlockFlooredToTheHour() {
    let e = UsageEvent.fixture(timestamp: hour0.addingTimeInterval(12 * 60), // 09:12
                               output: 10, requestId: "r1", messageId: "m1")
    let blocks = SessionBlocks.segment([e])
    #expect(blocks.count == 1)
    #expect(blocks[0].start == hour0)                          // floored to 09:00
    #expect(blocks[0].end == hour0.addingTimeInterval(fiveHours))
    #expect(blocks[0].totals.output == 10)
}

@Test func eventsWithinFiveHoursShareOneBlock() {
    let events = [
        UsageEvent.fixture(timestamp: hour0.addingTimeInterval(12 * 60),
                           output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: hour0.addingTimeInterval(2 * 3600),
                           output: 20, requestId: "r2", messageId: "m2"),
    ]
    let blocks = SessionBlocks.segment(events)
    #expect(blocks.count == 1)
    #expect(blocks[0].totals.output == 30)
}

@Test func eventAtExactlyFiveHoursAfterStartOpensANewBlock() {
    // Boundary is half-open: [start, start+5h). An event exactly at start+5h is out.
    let events = [
        UsageEvent.fixture(timestamp: hour0, output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: hour0.addingTimeInterval(fiveHours),
                           output: 20, requestId: "r2", messageId: "m2"),
    ]
    let blocks = SessionBlocks.segment(events)
    #expect(blocks.count == 2)
    #expect(blocks[0].totals.output == 10)
    #expect(blocks[1].start == hour0.addingTimeInterval(fiveHours))  // 14:00
    #expect(blocks[1].totals.output == 20)
}

@Test func idleGapInsideTheWindowStaysInTheSameBlock() {
    // Claude's 5h window runs five hours of wall-clock from the first message —
    // going idle does NOT reset it. A 4h gap inside the window is still one block.
    let events = [
        UsageEvent.fixture(timestamp: hour0, output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: hour0.addingTimeInterval(4 * 3600),
                           output: 20, requestId: "r2", messageId: "m2"),
    ]
    let blocks = SessionBlocks.segment(events)
    #expect(blocks.count == 1)
    #expect(blocks[0].totals.output == 30)
}

@Test func aLongIdleGapClosesTheBlockOnlyByAgingOut() {
    let events = [
        UsageEvent.fixture(timestamp: hour0, output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: hour0.addingTimeInterval(fiveHours + 1800),
                           output: 20, requestId: "r2", messageId: "m2"),
    ]
    let blocks = SessionBlocks.segment(events)
    #expect(blocks.count == 2)
    #expect(blocks[1].start == hour0.addingTimeInterval(fiveHours))  // 14:30 floored to 14:00
}

@Test func unsortedInputIsSegmentedInTimeOrder() {
    let late = UsageEvent.fixture(timestamp: hour0.addingTimeInterval(2 * 3600),
                                  output: 20, requestId: "r2", messageId: "m2")
    let early = UsageEvent.fixture(timestamp: hour0, output: 10, requestId: "r1", messageId: "m1")
    let blocks = SessionBlocks.segment([late, early])
    #expect(blocks.count == 1)
    #expect(blocks[0].start == hour0)
    #expect(blocks[0].totals.output == 30)
}

@Test func currentReturnsTheOpenBlock() {
    let blocks = SessionBlocks.segment([
        UsageEvent.fixture(timestamp: hour0, output: 10, requestId: "r1", messageId: "m1")
    ])
    let now = hour0.addingTimeInterval(3600)
    #expect(SessionBlocks.current(blocks, now: now)?.totals.output == 10)
}

@Test func currentIncludesTheExactBlockStart() {
    let blocks = SessionBlocks.segment([
        UsageEvent.fixture(timestamp: hour0, output: 10, requestId: "r1", messageId: "m1")
    ])
    // The lower bound is inclusive; only `end` is exclusive.
    #expect(SessionBlocks.current(blocks, now: hour0)?.totals.output == 10)
}

@Test func currentIsNilOnceTheBlockHasClosed() {
    // The whole point of anchoring: 5h usage resets to zero at the block boundary
    // instead of decaying like a trailing window.
    let blocks = SessionBlocks.segment([
        UsageEvent.fixture(timestamp: hour0, output: 10, requestId: "r1", messageId: "m1")
    ])
    let now = hour0.addingTimeInterval(fiveHours)   // exactly at end — half-open
    #expect(SessionBlocks.current(blocks, now: now) == nil)
}

@Test func currentIsNilBeforeAnyBlockStarts() {
    let blocks = SessionBlocks.segment([
        UsageEvent.fixture(timestamp: hour0, output: 10, requestId: "r1", messageId: "m1")
    ])
    #expect(SessionBlocks.current(blocks, now: hour0.addingTimeInterval(-60)) == nil)
}

@Test func currentPicksTheLatestBlockWhenSeveralExist() {
    let blocks = SessionBlocks.segment([
        UsageEvent.fixture(timestamp: hour0, output: 10, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: hour0.addingTimeInterval(3 * 86_400),
                           output: 20, requestId: "r2", messageId: "m2"),
    ])
    #expect(blocks.count == 2)
    let now = hour0.addingTimeInterval(3 * 86_400 + 3600)
    #expect(SessionBlocks.current(blocks, now: now)?.totals.output == 20)
}
