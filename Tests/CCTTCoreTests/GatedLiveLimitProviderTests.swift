import Foundation
import Testing
@testable import CCTTCore

/// Records whether the wrapped provider was consulted.
final class CountingProvider: LiveLimitProvider, @unchecked Sendable {
    let result: LiveFetchResult
    private(set) var calls = 0
    init(_ result: LiveFetchResult) { self.result = result }
    func fetch() async -> LiveFetchResult { calls += 1; return result }
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
