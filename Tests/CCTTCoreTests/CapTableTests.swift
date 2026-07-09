import Testing
@testable import CCTTCore

@Test func bundledCoversKnownTiers() {
    #expect(CapTable.bundled.caps(forTier: "default_claude_pro") != nil)
    #expect(CapTable.bundled.caps(forTier: "default_claude_max_5x") != nil)
    #expect(CapTable.bundled.caps(forTier: "default_claude_max_20x") != nil)
}

@Test func max5xCapsAreOrdered() {
    let caps = CapTable.bundled.caps(forTier: "default_claude_max_5x")!
    #expect(caps.weeklyTokens > caps.fiveHourTokens)
}

@Test func unknownOrNilTierReturnsNil() {
    #expect(CapTable.bundled.caps(forTier: "nope") == nil)
    #expect(CapTable.bundled.caps(forTier: nil) == nil)
}

@Test func bundledIsVersioned() {
    #expect(!CapTable.bundled.version.isEmpty)
}
