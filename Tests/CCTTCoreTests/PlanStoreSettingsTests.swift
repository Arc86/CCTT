import Foundation
import Testing
@testable import CCTTCore

private let t0 = Date(timeIntervalSince1970: 1_783_000_000)

private func writeConfig(_ json: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-store-settings-\(UUID().uuidString).json")
    try! Data(json.utf8).write(to: url)
    return url
}

@MainActor
struct PlanStoreSettingsTests {

    @Test func manualPlanKindOverridesDetection() async {
        // Config says subscription, but the user forced API mode.
        let url = writeConfig(#"{"oauthAccount":{"organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x"}}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let settings = AppSettings(manualPlanKind: .api, apiMonthlyBudgetUSD: 100)

        let store = PlanStore(configURL: url, environment: [:],
                              settingsProvider: { settings }, clock: { t0 })
        await store.refresh(snapshot: .empty(now: t0))
        #expect(store.plan.kind == .api)
        #expect(store.plan.source == .manual)
        // API window present, budget applied.
        #expect(store.status.windows.contains { $0.kind == .month })
    }

    @Test func apiBudgetFromSettingsDrivesPercent() async {
        let url = writeConfig(#"{"apiKeyHelper":"echo key"}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let settings = AppSettings(apiMonthlyBudgetUSD: 10)

        let store = PlanStore(configURL: url,
                              environment: ["ANTHROPIC_API_KEY": "sk-test"],
                              settingsProvider: { settings }, clock: { t0 })
        await store.refresh(snapshot: .empty(now: t0))
        #expect(store.plan.kind == .api)
        let month = store.status.windows.first { $0.kind == .month }
        #expect(month != nil)
        #expect(month?.percent == 0)   // no spend yet, budget set
    }
}
