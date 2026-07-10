import Testing
@testable import CCTTCore

@Test func formatUSDHandlesMagnitudes() {
    #expect(DefaultPaths.formatUSD(0) == "$0")
    #expect(DefaultPaths.formatUSD(0.5) == "$0.50")
    #expect(DefaultPaths.formatUSD(1.234) == "$1.23")
    #expect(DefaultPaths.formatUSD(250) == "$250")
    #expect(DefaultPaths.formatUSD(12_300) == "$12.3K")
    #expect(DefaultPaths.formatUSD(2_500_000) == "$2.5M")
}

@Test func formatValueShowsNAForFullyUnpricedDollars() {
    let t = TokenTotals(input: 0, output: 100)
    // Every token unpriced → "n/a", not "$0".
    #expect(DefaultPaths.formatValue(totals: t, costUSD: 0, unit: .dollars,
                                     unpricedTokens: 100) == "n/a")
    // Same bucket in token unit is unaffected.
    #expect(DefaultPaths.formatValue(totals: t, costUSD: 0, unit: .tokens,
                                     unpricedTokens: 100) == DefaultPaths.formatTokens(100))
    // Partially priced → shows the (lower-bound) dollar figure, not n/a.
    #expect(DefaultPaths.formatValue(totals: t, costUSD: 3, unit: .dollars,
                                     unpricedTokens: 40) == DefaultPaths.formatUSD(3))
}

@Test func formatValueDispatchesOnUnit() {
    let t = TokenTotals(input: 1_000_000)
    #expect(DefaultPaths.formatValue(totals: t, costUSD: 5, unit: .tokens) == DefaultPaths.formatTokens(t.total))
    #expect(DefaultPaths.formatValue(totals: t, costUSD: 5, unit: .dollars) == DefaultPaths.formatUSD(5))
}
