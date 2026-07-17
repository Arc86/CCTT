import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

private func writeConfig(_ json: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-store-\(UUID().uuidString).json")
    try! Data(json.utf8).write(to: url)
    return url
}

/// Shared fixture config for the live-health/poll-schedule tests below — they
/// don't care about plan detection, just that a config file exists.
private let fixtureConfigURL = writeConfig(#"{"oauthAccount":{"organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x"}}"#)

/// A clock whose `now` can be advanced mid-test, so tests can simulate real
/// time passing between two `refresh()` calls (needed once `PlanStore` gates
/// fetches on elapsed time rather than on call order).
private final class MutableClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
@Test func refreshDetectsPlanAndComputesEstimate() async {
    let url = writeConfig(#"{"oauthAccount":{"organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x"}}"#)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PlanStore(configURL: url, environment: [:],
                          provider: UnavailableLiveLimitProvider(),
                          clock: { now })
    let snap = aggregate(
        events: [UsageEvent.fixture(timestamp: now.addingTimeInterval(-600),
                                    input: 1_000_000, output: 0,
                                    requestId: "r1", messageId: "m1")],
        parseErrors: 0, now: now)
    await store.refresh(snapshot: snap)
    #expect(store.plan.kind == .subscription)
    #expect(store.status.provenance == .estimated)
    #expect(abs(store.status.headlinePercent! - 0.2) < 1e-9)   // 1M / 5M cap
}

@MainActor
@Test func planStoreStartsEmpty() {
    let store = PlanStore(configURL: URL(fileURLWithPath: "/definitely/missing.json"),
                          clock: { Date(timeIntervalSince1970: 0) })
    #expect(store.status.headlinePercent == nil)
    #expect(store.plan.kind == .unknown)
}

@MainActor
@Test func refreshUsesLiveProviderWhenAvailable() async {
    let url = writeConfig(#"{"oauthAccount":{"organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x"}}"#)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PlanStore(configURL: url, environment: [:],
                          provider: StaticLiveLimitProvider(LiveLimits(fiveHourPercent: 0.9)),
                          clock: { now })
    await store.refresh(snapshot: aggregate(events: [], parseErrors: 0, now: now))
    #expect(store.status.provenance == .live)
    #expect(store.status.headlinePercent == 0.9)
}

// MARK: - Live health + adaptive polling

@MainActor
@Test func healthIsNilWhenLiveIsDisabled() async {
    let store = PlanStore(configURL: fixtureConfigURL,
                          provider: UnavailableLiveLimitProvider(),
                          clock: { now })
    await store.refresh(snapshot: .empty(now: now))
    #expect(store.status.liveHealth == nil)
    #expect(store.nextPollInterval == PollSchedule.base)
}

@MainActor
@Test func healthIsOkOnASuccessfulFetch() async {
    let store = PlanStore(configURL: fixtureConfigURL,
                          provider: StaticLiveLimitProvider(LiveLimits(fiveHourPercent: 0.4)),
                          clock: { now })
    await store.refresh(snapshot: .empty(now: now))
    #expect(store.status.liveHealth == .ok)
}

@MainActor
@Test func a401BecomesNeedsReauthAndBacksOffThePoll() async {
    let provider = ScriptedProvider([LiveFetchResult(limits: nil, outcome: .unauthorized)])
    let store = PlanStore(configURL: fixtureConfigURL, provider: provider, clock: { now })
    await store.refresh(snapshot: .empty(now: now))
    #expect(store.status.liveHealth == .needsReauth)
    #expect(store.nextPollInterval == PollSchedule.base * 2)
}

@MainActor
@Test func a429BecomesRateLimitedCarryingItsResumeTime() async {
    let until = now.addingTimeInterval(600)
    let provider = ScriptedProvider([
        LiveFetchResult(limits: nil, outcome: .rateLimited(retryAfter: until))
    ])
    let store = PlanStore(configURL: fixtureConfigURL, provider: provider, clock: { now })
    await store.refresh(snapshot: .empty(now: now))
    #expect(store.status.liveHealth == .rateLimited(until: until))
    #expect(store.nextPollInterval == 600)
}

@MainActor
@Test func aSuccessAfterBackoffSnapsThePollBackToBase() async {
    // The fetch is now gated on elapsed time (Finding 1), so a genuine second
    // fetch requires the clock to actually advance past the backed-off
    // interval — otherwise the second `refresh()` would be throttled and never
    // reach the provider at all.
    let clock = MutableClock(now)
    let provider = ScriptedProvider([
        LiveFetchResult(limits: nil, outcome: .transient),
        LiveFetchResult(limits: LiveLimits(fiveHourPercent: 0.4), outcome: .success),
    ])
    let store = PlanStore(configURL: fixtureConfigURL, provider: provider, clock: { clock.now })
    await store.refresh(snapshot: .empty(now: clock.now))
    #expect(store.nextPollInterval == PollSchedule.base * 2)
    clock.now = clock.now.addingTimeInterval(PollSchedule.base * 2)
    await store.refresh(snapshot: .empty(now: clock.now))
    #expect(store.nextPollInterval == PollSchedule.base)
}

// MARK: - Finding 1: the fetch, not the whole refresh, is what's throttled

@MainActor
@Test func aThrottledRefreshDoesNotCallTheProviderAgain() async {
    let provider = CountingProvider(LiveFetchResult(limits: nil, outcome: .transient))
    let store = PlanStore(configURL: fixtureConfigURL, provider: provider, clock: { now })
    await store.refresh(snapshot: .empty(now: now))
    #expect(provider.calls == 1)
    await store.refresh(snapshot: .empty(now: now))
    #expect(provider.calls == 1)   // still inside the backoff window — no re-hit
}

@MainActor
@Test func refreshStillProducesAStatusWhileTheFetchIsThrottled() async {
    let provider = CountingProvider(LiveFetchResult(limits: nil, outcome: .transient))
    let store = PlanStore(configURL: fixtureConfigURL, provider: provider, clock: { now })
    await store.refresh(snapshot: .empty(now: now))
    #expect(provider.calls == 1)

    // A fresh local snapshot arrives (local JSONL ingest keeps running even
    // while the live fetch is throttled) — the status must reflect it, not go
    // blank or stale-out, even though no new fetch happens.
    let snap = aggregate(
        events: [UsageEvent.fixture(timestamp: now.addingTimeInterval(-600),
                                    input: 1_000_000, output: 0,
                                    requestId: "r2", messageId: "m2")],
        parseErrors: 0, now: now)
    await store.refresh(snapshot: snap)
    #expect(provider.calls == 1)   // still throttled
    #expect(store.status.headlinePercent != nil)
    #expect(abs(store.status.headlinePercent! - 0.2) < 1e-9)   // 1M / 5M cap, estimate path
}

@MainActor
@Test func theFetchResumesOnceTheThrottleIntervalElapses() async {
    let clock = MutableClock(now)
    let provider = CountingProvider(script: [
        LiveFetchResult(limits: nil, outcome: .transient),
        LiveFetchResult(limits: LiveLimits(fiveHourPercent: 0.4), outcome: .success),
    ])
    let store = PlanStore(configURL: fixtureConfigURL, provider: provider, clock: { clock.now })
    await store.refresh(snapshot: .empty(now: clock.now))
    #expect(provider.calls == 1)

    clock.now = clock.now.addingTimeInterval(PollSchedule.base * 2)
    await store.refresh(snapshot: .empty(now: clock.now))
    #expect(provider.calls == 2)
    #expect(store.status.provenance == .live)
    #expect(store.status.headlinePercent == 0.4)
}

@MainActor
@Test func disabledNeverThrottlesTheFetch() async {
    let provider = CountingProvider(LiveFetchResult(limits: nil, outcome: .disabled))
    let store = PlanStore(configURL: fixtureConfigURL, provider: provider, clock: { now })
    await store.refresh(snapshot: .empty(now: now))
    await store.refresh(snapshot: .empty(now: now))
    await store.refresh(snapshot: .empty(now: now))
    #expect(provider.calls == 3)   // disabled is free and must never be gated
    #expect(store.status.liveHealth == nil)
}

// MARK: - User-initiated retry must never be swallowed by backoff

@MainActor
@Test func resetFetchThrottleForcesTheNextRefreshToCallTheProviderWithoutAdvancingTheClock() async {
    let provider = CountingProvider(LiveFetchResult(limits: nil, outcome: .transient))
    let store = PlanStore(configURL: fixtureConfigURL, provider: provider, clock: { now })
    await store.refresh(snapshot: .empty(now: now))
    #expect(provider.calls == 1)

    // Still well inside the backoff window an ordinary refresh would skip it —
    // confirm the gate is actually armed before clearing it.
    await store.refresh(snapshot: .empty(now: now))
    #expect(provider.calls == 1)

    store.resetFetchThrottle()
    await store.refresh(snapshot: .empty(now: now))
    #expect(provider.calls == 2)   // throttle cleared — the provider was hit again, clock unchanged
}
