import Testing
@testable import CCTTCore

@Test func unknownConfigHasSensibleDefaults() {
    let c = PlanConfig.unknown()
    #expect(c.kind == .unknown)
    #expect(c.source == .fallback)
    #expect(c.currency == "USD")
    #expect(c.hasExtraUsageEnabled == false)
    #expect(c.creditGrant == nil)
}

@Test func planLabelMapsKnownTiers() {
    #expect(PlanConfig(kind: .subscription, rateLimitTier: "default_claude_pro").planLabel == "Pro")
    #expect(PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x").planLabel == "Max 5x")
    #expect(PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_20x").planLabel == "Max 20x")
    #expect(PlanConfig(kind: .api).planLabel == "API")
    #expect(PlanConfig(kind: .unknown).planLabel == "Unknown plan")
}

/// Enterprise is always labelled "Enterprise" — never the consumer tier name,
/// even when it carries a `max_*` rate-limit tier (the tier only sizes caps).
@Test func enterpriseIsAlwaysLabelledEnterprise() {
    #expect(PlanConfig(kind: .enterprise, organizationType: "enterprise").planLabel == "Enterprise")
    #expect(PlanConfig(kind: .enterprise, rateLimitTier: "default_claude_max_5x").planLabel == "Enterprise")
    #expect(PlanConfig(kind: .enterprise, rateLimitTier: "default_claude_max_20x").planLabel == "Enterprise")
}
