import Foundation
import Testing
@testable import CCTTCore

/// Records whether the wrapped provider was consulted.
final class CountingProvider: LiveLimitProvider, @unchecked Sendable {
    let value: LiveLimits?
    private(set) var calls = 0
    init(_ value: LiveLimits?) { self.value = value }
    func fetch() async -> LiveLimits? { calls += 1; return value }
}

struct GatedLiveLimitProviderTests {

    @Test func passesThroughWhenEnabled() async {
        let inner = CountingProvider(LiveLimits(fiveHourPercent: 0.4))
        let gated = GatedLiveLimitProvider(wrapping: inner, isEnabled: { true })
        #expect(await gated.fetch()?.fiveHourPercent == 0.4)
        #expect(inner.calls == 1)
    }

    @Test func returnsNilWithoutCallingWhenDisabled() async {
        let inner = CountingProvider(LiveLimits(fiveHourPercent: 0.4))
        let gated = GatedLiveLimitProvider(wrapping: inner, isEnabled: { false })
        #expect(await gated.fetch() == nil)
        #expect(inner.calls == 0)
    }
}
