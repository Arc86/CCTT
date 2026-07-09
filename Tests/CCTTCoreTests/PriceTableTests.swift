import Testing
@testable import CCTTCore

@Test func opusPricingMatchesPublished() {
    let price = PriceTable.bundled.price(forModel: "claude-opus-4-8")!
    // 1M input @ $5 + 1M output @ $25 = $30
    let cost = price.costUSD(for: TokenTotals(input: 1_000_000, output: 1_000_000))
    #expect(abs(cost - 30) < 1e-6)
}

@Test func matchesFamilyBySubstring() {
    #expect(PriceTable.bundled.price(forModel: "claude-opus-4-8[1m]") != nil)
    #expect(PriceTable.bundled.price(forModel: "claude-haiku-4-5-20251001") != nil)
    #expect(PriceTable.bundled.price(forModel: "claude-sonnet-5") != nil)
}

@Test func costByModelSumsAcrossRollups() {
    let rollups = [
        Rollup(key: "claude-opus-4-8", totals: TokenTotals(output: 1_000_000)),  // $25
        Rollup(key: "claude-haiku-4-5", totals: TokenTotals(output: 1_000_000)), // $5
    ]
    #expect(abs(PriceTable.bundled.costUSD(forByModel: rollups) - 30) < 1e-6)
}

@Test func unknownModelContributesZero() {
    #expect(PriceTable.bundled.price(forModel: "gpt-4") == nil)
    let rollups = [Rollup(key: "gpt-4", totals: TokenTotals(output: 1_000_000))]
    #expect(PriceTable.bundled.costUSD(forByModel: rollups) == 0)
}

@Test func cacheReadIsCheaperThanInput() {
    let price = PriceTable.bundled.price(forModel: "claude-opus-4-8")!
    #expect(price.cacheReadPerMTok < price.inputPerMTok)
}
