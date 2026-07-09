import Testing
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
