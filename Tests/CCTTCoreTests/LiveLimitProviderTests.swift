import Foundation
import Testing
@testable import CCTTCore

@Test func staticProviderReturnsItsValueAsSuccess() async {
    let p = StaticLiveLimitProvider(LiveLimits(fiveHourPercent: 0.3, weeklyPercent: 0.1))
    let out = await p.fetch()
    #expect(out.limits?.fiveHourPercent == 0.3)
    #expect(out.outcome == .success)
}

@Test func staticProviderWithNilReportsDisabled() async {
    let out = await StaticLiveLimitProvider(nil).fetch()
    #expect(out.limits == nil)
    #expect(out.outcome == .disabled)
}

@Test func unavailableProviderReportsDisabled() async {
    let out = await UnavailableLiveLimitProvider().fetch()
    #expect(out.limits == nil)
    #expect(out.outcome == .disabled)
}

/// Yields a scripted sequence of results, one per call.
final class ScriptedProvider: LiveLimitProvider, @unchecked Sendable {
    private var script: [LiveFetchResult]
    init(_ script: [LiveFetchResult]) { self.script = script }
    func fetch() async -> LiveFetchResult {
        script.isEmpty ? .disabled : script.removeFirst()
    }
}

struct StickyLiveLimitProviderTests {

    @Test func servesLastGoodValueWhileReportingWhyTheFreshFetchFailed() async {
        // The core of the sticky contract: a stale-but-real number beats the tier
        // estimate, but the *reason* must still reach the UI.
        let inner = ScriptedProvider([
            LiveFetchResult(limits: LiveLimits(fiveHourPercent: 0.5), outcome: .success),
            LiveFetchResult(limits: nil, outcome: .rateLimited(retryAfter: nil)),
        ])
        let sticky = StickyLiveLimitProvider(wrapping: inner)

        let first = await sticky.fetch()
        #expect(first.limits?.fiveHourPercent == 0.5)
        #expect(first.outcome == .success)

        let second = await sticky.fetch()
        #expect(second.limits?.fiveHourPercent == 0.5)              // stale but real
        #expect(second.outcome == .rateLimited(retryAfter: nil))    // reason survives
    }

    @Test func returnsNoLimitsWhenNothingGoodWasEverSeen() async {
        let inner = ScriptedProvider([LiveFetchResult(limits: nil, outcome: .unauthorized)])
        let sticky = StickyLiveLimitProvider(wrapping: inner)
        let out = await sticky.fetch()
        #expect(out.limits == nil)
        #expect(out.outcome == .unauthorized)
    }

    @Test func passesDisabledStraightThroughWithoutServingStale() async {
        // Turning live limits off must cut over to estimates immediately — serving
        // a cached live number after opt-out would be wrong.
        let inner = ScriptedProvider([
            LiveFetchResult(limits: LiveLimits(fiveHourPercent: 0.5), outcome: .success),
            .disabled,
        ])
        let sticky = StickyLiveLimitProvider(wrapping: inner)
        _ = await sticky.fetch()
        let out = await sticky.fetch()
        #expect(out.limits == nil)
        #expect(out.outcome == .disabled)
    }

    @Test func aFreshSuccessReplacesTheStaleValue() async {
        let inner = ScriptedProvider([
            LiveFetchResult(limits: LiveLimits(fiveHourPercent: 0.5), outcome: .success),
            LiveFetchResult(limits: nil, outcome: .transient),
            LiveFetchResult(limits: LiveLimits(fiveHourPercent: 0.6), outcome: .success),
        ])
        let sticky = StickyLiveLimitProvider(wrapping: inner)
        _ = await sticky.fetch()
        _ = await sticky.fetch()
        let out = await sticky.fetch()
        #expect(out.limits?.fiveHourPercent == 0.6)
        #expect(out.outcome == .success)
    }

    // The two below are CARRIED OVER from the pre-refactor suite, adapted to
    // `LiveFetchResult`. They are the only tests pinning `persist()`/`load()` and the
    // word "indefinitely" — both must-survive behaviours. Do not drop them.

    @Test func keepsServingLastGoodIndefinitely() async {
        // "Indefinitely" is the contract: the endpoint 429s for extended stretches and
        // the tier estimate is wildly off, so a stale-but-real number always wins.
        // No expiry may creep in.
        var script = [LiveFetchResult(limits: LiveLimits(fiveHourPercent: 0.5), outcome: .success)]
        script.append(contentsOf: Array(repeating: LiveFetchResult(limits: nil, outcome: .transient),
                                        count: 50))
        let sticky = StickyLiveLimitProvider(wrapping: ScriptedProvider(script))
        _ = await sticky.fetch()
        for _ in 0..<50 {
            #expect(await sticky.fetch().limits?.fiveHourPercent == 0.5)
        }
    }

    @Test func persistsLastGoodAcrossRestart() async throws {
        // A second instance built from the same cacheURL must recover the last-good
        // sample, so the real number survives an app restart while still throttled.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("live-limits.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let seed = LiveFetchResult(limits: LiveLimits(fiveHourPercent: 0.5), outcome: .success)
        let first = StickyLiveLimitProvider(wrapping: ScriptedProvider([seed]), cacheURL: url)
        _ = await first.fetch()
        #expect(FileManager.default.fileExists(atPath: url.path))   // proves the disk write happened

        let restarted = StickyLiveLimitProvider(
            wrapping: ScriptedProvider([LiveFetchResult(limits: nil, outcome: .transient)]),
            cacheURL: url)
        let out = await restarted.fetch()
        #expect(out.limits?.fiveHourPercent == 0.5)   // recovered from disk
        #expect(out.outcome == .transient)
    }
}
