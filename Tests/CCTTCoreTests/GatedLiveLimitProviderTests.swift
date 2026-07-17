import Foundation
import Testing
@testable import CCTTCore

/// Records whether the wrapped provider was consulted. Also usable as a
/// scripted sequence (`init(script:)`) when a test needs both the call count
/// and successive different outcomes — e.g. proving a throttled `PlanStore`
/// fetch is skipped, then resumes once the schedule allows it again.
final class CountingProvider: LiveLimitProvider, @unchecked Sendable {
    private var script: [LiveFetchResult]
    private(set) var calls = 0
    init(_ result: LiveFetchResult) { self.script = [result] }
    init(script: [LiveFetchResult]) { self.script = script }
    func fetch() async -> LiveFetchResult {
        calls += 1
        guard !script.isEmpty else { return .disabled }
        // A single-result double repeats its one result forever; a scripted
        // sequence is consumed one call at a time, holding its last entry.
        return script.count > 1 ? script.removeFirst() : script[0]
    }
}

struct GatedLiveLimitProviderTests {

    @Test func passesThroughWhenEnabled() async {
        let inner = CountingProvider(LiveFetchResult(limits: LiveLimits(fiveHourPercent: 0.4),
                                                     outcome: .success))
        let gated = GatedLiveLimitProvider(wrapping: inner, isEnabled: { true })
        let out = await gated.fetch()
        #expect(out.limits?.fiveHourPercent == 0.4)
        #expect(out.outcome == .success)
        #expect(inner.calls == 1)
    }

    @Test func reportsDisabledWithoutConsultingTheWrappedProvider() async {
        // The opt-in guarantee: no Keychain read and no network call until enabled.
        let inner = CountingProvider(LiveFetchResult(limits: LiveLimits(fiveHourPercent: 0.4),
                                                     outcome: .success))
        let gated = GatedLiveLimitProvider(wrapping: inner, isEnabled: { false })
        let out = await gated.fetch()
        #expect(out.limits == nil)
        #expect(out.outcome == .disabled)
        #expect(inner.calls == 0)
    }
}
