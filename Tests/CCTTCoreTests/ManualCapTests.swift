import Foundation
import Testing
@testable import CCTTCore

/// When no tier cap is known (enterprise or an unrecognised tier), a user-entered
/// manual cap drives the estimate instead of showing "no limit".
struct ManualCapTests {

    private func snapshot(fiveHour: Int, weekly: Int) -> UsageSnapshot {
        UsageSnapshot(overall: .zero, byProject: [], byModel: [], bySession: [],
                      byAgentKind: [], bySkill: [], byPlugin: [],
                      fiveHour: TokenTotals(input: fiveHour),
                      weekly: TokenTotals(input: weekly),
                      monthToDate: .zero, monthByModel: [],
                      parseErrors: 0, generatedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func manualCapsDriveEstimateWhenTierUnknown() {
        let plan = PlanConfig(kind: .enterprise, rateLimitTier: nil,
                              organizationType: "enterprise_x")
        let status = LimitEngine.status(
            plan: plan, snapshot: snapshot(fiveHour: 500_000, weekly: 1_000_000),
            caps: .bundled, prices: .bundled, live: nil,
            apiMonthlyBudgetUSD: nil,
            manualCaps: WindowCaps(fiveHourTokens: 1_000_000, weeklyTokens: 4_000_000),
            now: Date(timeIntervalSince1970: 0))

        let five = status.windows.first { $0.kind == .fiveHour }
        #expect(five?.percent == 0.5)          // 500k / 1M
        #expect(five?.capTokens == 1_000_000)
        #expect(five?.provenance == .estimated)
    }

    @Test func tierCapsWinOverManualWhenBothPresent() {
        let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
        let status = LimitEngine.status(
            plan: plan, snapshot: snapshot(fiveHour: 1_000_000, weekly: 0),
            caps: .bundled, prices: .bundled, live: nil, apiMonthlyBudgetUSD: nil,
            manualCaps: WindowCaps(fiveHourTokens: 2_000_000, weeklyTokens: 8_000_000),
            now: Date(timeIntervalSince1970: 0))
        let five = status.windows.first { $0.kind == .fiveHour }
        #expect(five?.capTokens == 5_000_000)   // bundled tier cap, not manual
    }
}
