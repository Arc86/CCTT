import Testing
import Foundation
@testable import CCTTCore

private func writeConfig(_ json: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-cfg-\(UUID().uuidString).json")
    try! Data(json.utf8).write(to: url)
    return url
}

@Test func detectsMaxSubscription() {
    let url = writeConfig(#"{"oauthAccount":{"billingType":"stripe_subscription","organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x","hasExtraUsageEnabled":false,"displayName":"Jesper"}}"#)
    defer { try? FileManager.default.removeItem(at: url) }
    let c = PlanDetector.detect(configURL: url, environment: [:])
    #expect(c.kind == .subscription)
    #expect(c.rateLimitTier == "default_claude_max_5x")
    #expect(c.displayName == "Jesper")
    #expect(c.source == .detected)
}

@Test func detectsProSubscription() {
    let url = writeConfig(#"{"oauthAccount":{"organizationType":"claude_pro","organizationRateLimitTier":"default_claude_pro"}}"#)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(PlanDetector.detect(configURL: url, environment: [:]).kind == .subscription)
}

@Test func detectsApiFromEnvKey() {
    let url = writeConfig(#"{"oauthAccount":{"organizationType":"claude_max"}}"#)
    defer { try? FileManager.default.removeItem(at: url) }
    let c = PlanDetector.detect(configURL: url, environment: ["ANTHROPIC_API_KEY": "sk-ant-xxx"])
    #expect(c.kind == .api)
    #expect(c.source == .detected)
}

@Test func detectsEnterprise() {
    let url = writeConfig(#"{"oauthAccount":{"organizationType":"enterprise","seatTier":"standard"}}"#)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(PlanDetector.detect(configURL: url, environment: [:]).kind == .enterprise)
}

@Test func ambiguousFallsBackToUnknown() {
    let url = writeConfig(#"{"oauthAccount":{"organizationType":"something_else"}}"#)
    defer { try? FileManager.default.removeItem(at: url) }
    let c = PlanDetector.detect(configURL: url, environment: [:])
    #expect(c.kind == .unknown)
    #expect(c.source == .fallback)
}

@Test func missingFileIsUnknown() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-missing-\(UUID().uuidString).json")
    #expect(PlanDetector.detect(configURL: url, environment: [:]).kind == .unknown)
}

@Test func readsCreditGrantForMatchingOrg() {
    let url = writeConfig(#"{"oauthAccount":{"organizationType":"claude_max","organizationUuid":"org-1","hasExtraUsageEnabled":true},"overageCreditGrantCache":{"org-1":{"info":{"available":true,"eligible":true,"granted":true,"amount_minor_units":5000,"currency":"EUR"}}}}"#)
    defer { try? FileManager.default.removeItem(at: url) }
    let c = PlanDetector.detect(configURL: url, environment: [:])
    #expect(c.hasExtraUsageEnabled == true)
    #expect(c.creditGrant?.available == true)
    #expect(c.creditGrant?.amountMinorUnits == 5000)
    #expect(c.creditGrant?.currency == "EUR")
}
