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

@Test func formatValueDispatchesOnUnit() {
    let t = TokenTotals(input: 1_000_000)
    #expect(DefaultPaths.formatValue(totals: t, costUSD: 5, unit: .tokens) == DefaultPaths.formatTokens(t.total))
    #expect(DefaultPaths.formatValue(totals: t, costUSD: 5, unit: .dollars) == DefaultPaths.formatUSD(5))
}
