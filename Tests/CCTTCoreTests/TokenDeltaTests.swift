import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

@Test func tokenDeltaRisesVersusPreviousWindow() {
    let events = [
        // previous 7d window ([now-14d, now-7d]): 100 tokens
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-10 * 86_400),
                           input: 0, output: 100, requestId: "r0", messageId: "m0"),
        // current 7d window: 200 tokens
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-1 * 86_400),
                           input: 0, output: 100, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-2 * 86_400),
                           input: 0, output: 100, requestId: "r2", messageId: "m2"),
    ]
    let d = tokenDelta(events: events, range: .last7Days, now: now)
    #expect(d != nil)
    #expect(abs(d! - 1.0) < 1e-9)   // +100%
}

@Test func tokenDeltaFallsVersusPreviousWindow() {
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-10 * 86_400),
                           input: 0, output: 200, requestId: "r0", messageId: "m0"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-1 * 86_400),
                           input: 0, output: 100, requestId: "r1", messageId: "m1"),
    ]
    let d = tokenDelta(events: events, range: .last7Days, now: now)
    #expect(d != nil)
    #expect(abs(d! - (-0.5)) < 1e-9)   // -50%
}

@Test func tokenDeltaIsNilForAllTime() {
    let events = [UsageEvent.fixture(timestamp: now.addingTimeInterval(-1 * 86_400),
                                     requestId: "r1", messageId: "m1")]
    #expect(tokenDelta(events: events, range: .all, now: now) == nil)
}

@Test func tokenDeltaIsNilForPartialWeek() {
    // A partial calendar week has no comparable full previous window.
    let events = [UsageEvent.fixture(timestamp: now.addingTimeInterval(-3600),
                                     requestId: "r1", messageId: "m1")]
    #expect(tokenDelta(events: events, range: .thisWeek, now: now) == nil)
}

@Test func tokenDeltaIsNilWithoutABaseline() {
    // Usage only in the current window → no previous-period baseline to divide by.
    let events = [UsageEvent.fixture(timestamp: now.addingTimeInterval(-1 * 86_400),
                                     input: 0, output: 100, requestId: "r1", messageId: "m1")]
    #expect(tokenDelta(events: events, range: .last7Days, now: now) == nil)
}

@Test func tokenDeltaDeduplicatesBeforeComparing() {
    // The same (requestId, messageId) streamed twice must count once (keep-last).
    let events = [
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-10 * 86_400),
                           input: 0, output: 100, requestId: "r0", messageId: "m0"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-1 * 86_400),
                           input: 0, output: 100, requestId: "r1", messageId: "m1"),
        UsageEvent.fixture(timestamp: now.addingTimeInterval(-1 * 86_400),
                           input: 0, output: 100, requestId: "r1", messageId: "m1"),
    ]
    let d = tokenDelta(events: events, range: .last7Days, now: now)
    #expect(d != nil)
    #expect(abs(d! - 0.0) < 1e-9)   // current 100 vs previous 100, dupes collapsed
}
