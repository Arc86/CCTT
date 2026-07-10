import Testing
import Foundation
@testable import CCTTCore

@Test func unavailableProviderReturnsNil() async {
    #expect(await UnavailableLiveLimitProvider().fetch() == nil)
}

@Test func staticProviderReturnsValue() async {
    let value = LiveLimits(fiveHourPercent: 0.3, weeklyPercent: 0.1)
    let result = await StaticLiveLimitProvider(value).fetch()
    #expect(result?.fiveHourPercent == 0.3)
    #expect(result?.weeklyPercent == 0.1)
}

/// Yields a scripted sequence of results, one per `fetch()`, so tests can
/// simulate a flaky upstream (a good poll followed by transient failures).
private actor ScriptedLiveLimitProvider: LiveLimitProvider {
    private var results: [LiveLimits?]
    private(set) var callCount = 0
    init(_ results: [LiveLimits?]) { self.results = results }
    func fetch() async -> LiveLimits? {
        callCount += 1
        return results.isEmpty ? nil : results.removeFirst()
    }
}

private let stickyBase = Date(timeIntervalSince1970: 1_783_000_000)

@Test func stickyServesLastGoodThroughTransientFailure() async {
    let upstream = ScriptedLiveLimitProvider([
        LiveLimits(fiveHourPercent: 0.5),   // good
        nil,                                 // transient blip
        LiveLimits(fiveHourPercent: 0.6),   // recovered
    ])
    let sticky = StickyLiveLimitProvider(wrapping: upstream)

    #expect(await sticky.fetch()?.fiveHourPercent == 0.5)
    #expect(await sticky.fetch()?.fiveHourPercent == 0.5) // served through the blip
    #expect(await sticky.fetch()?.fiveHourPercent == 0.6) // upstream recovered
}

/// The endpoint can 429 for long, indefinite stretches; we always prefer the
/// stale-but-real live figure to the wildly-off tier estimate, forever.
@Test func stickyKeepsServingLastGoodIndefinitely() async {
    let upstream = ScriptedLiveLimitProvider(
        [LiveLimits(fiveHourPercent: 0.5)] + Array(repeating: nil, count: 50))
    let sticky = StickyLiveLimitProvider(wrapping: upstream)

    #expect(await sticky.fetch()?.fiveHourPercent == 0.5)   // seed
    for _ in 0..<50 { #expect(await sticky.fetch()?.fiveHourPercent == 0.5) }
}

@Test func stickyPassesThroughWhenNeverSucceeds() async {
    let upstream = ScriptedLiveLimitProvider([nil, nil])
    let sticky = StickyLiveLimitProvider(wrapping: upstream)
    #expect(await sticky.fetch() == nil)
    #expect(await sticky.fetch() == nil)
}

/// The last-good sample (age included) survives a restart: a fresh provider
/// reading from the same cache file serves it even while upstream is failing.
@Test func stickyPersistsLastGoodAcrossRestart() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-live-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    let observed = stickyBase
    let seed = LiveLimits(fiveHourPercent: 0.42, weeklyPercent: 0.11, observedAt: observed)
    let first = StickyLiveLimitProvider(
        wrapping: ScriptedLiveLimitProvider([seed]), cacheURL: url)
    #expect(await first.fetch()?.fiveHourPercent == 0.42)   // writes cache

    // Simulate a relaunch while the endpoint is throttled (upstream only nils).
    let restarted = StickyLiveLimitProvider(
        wrapping: ScriptedLiveLimitProvider([nil, nil]), cacheURL: url)
    let served = await restarted.fetch()
    #expect(served?.fiveHourPercent == 0.42)
    #expect(served?.weeklyPercent == 0.11)
    #expect(served?.observedAt == observed)   // original age preserved for the UI
}
