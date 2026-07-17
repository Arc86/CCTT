import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_784_278_800)

@Test func startsAtTheBaseInterval() {
    #expect(PollSchedule().interval == PollSchedule.base)
}

@Test func successResetsToBase() {
    let backedOff = PollSchedule(interval: 900)
    #expect(backedOff.next(after: .success, now: now).interval == PollSchedule.base)
}

@Test func disabledResetsToBase() {
    let backedOff = PollSchedule(interval: 900)
    #expect(backedOff.next(after: .disabled, now: now).interval == PollSchedule.base)
}

@Test func transientDoublesTheInterval() {
    #expect(PollSchedule(interval: 120).next(after: .transient, now: now).interval == 240)
}

@Test func malformedDoublesTheInterval() {
    #expect(PollSchedule(interval: 120).next(after: .malformed, now: now).interval == 240)
}

@Test func unauthorizedBacksOffButDoesNotStop() {
    // Claude Code refreshes the token out from under us, so a 401 may self-heal.
    #expect(PollSchedule(interval: 120).next(after: .unauthorized, now: now).interval == 240)
}

@Test func backoffIsCapped() {
    let s = PollSchedule(interval: PollSchedule.cap).next(after: .transient, now: now)
    #expect(s.interval == PollSchedule.cap)
}

@Test func rateLimitedWithoutRetryAfterDoubles() {
    let s = PollSchedule(interval: 120).next(after: .rateLimited(retryAfter: nil), now: now)
    #expect(s.interval == 240)
}

@Test func rateLimitedHonoursALongerRetryAfter() {
    let s = PollSchedule(interval: 120)
        .next(after: .rateLimited(retryAfter: now.addingTimeInterval(600)), now: now)
    #expect(s.interval == 600)
}

@Test func rateLimitedIgnoresAShorterRetryAfterInFavourOfBackoff() {
    // Never poll sooner than our own backoff, even if the server says we may.
    let s = PollSchedule(interval: 300)
        .next(after: .rateLimited(retryAfter: now.addingTimeInterval(10)), now: now)
    #expect(s.interval == 600)   // 300 * 2, not 10
}

@Test func rateLimitedRetryAfterIsCapped() {
    let s = PollSchedule(interval: 120)
        .next(after: .rateLimited(retryAfter: now.addingTimeInterval(86_400)), now: now)
    #expect(s.interval == PollSchedule.cap)
}
