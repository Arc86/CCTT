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

@Test func planLabelFallsBackToOrgType() {
    #expect(PlanConfig(kind: .enterprise, organizationType: "enterprise").planLabel == "enterprise")
}
