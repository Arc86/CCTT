import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

private func snapshot(fiveHour: TokenTotals = .zero, weekly: TokenTotals = .zero,
                      monthToDate: TokenTotals = .zero, byModel: [Rollup] = [],
                      monthByModel: [Rollup] = []) -> UsageSnapshot {
    UsageSnapshot(overall: .zero, byProject: [], byModel: byModel, bySession: [],
                  byAgentKind: [], bySkill: [], byPlugin: [],
                  fiveHour: fiveHour, weekly: weekly, monthToDate: monthToDate,
                  monthByModel: monthByModel, parseErrors: 0, generatedAt: now)
}

@Test func subscriptionEstimatesFromCapTable() {
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
    let snap = snapshot(fiveHour: TokenTotals(input: 1_000_000),   // vs 5M cap → 0.2
                        weekly: TokenTotals(input: 5_000_000))     // vs 50M cap → 0.1
    let status = LimitEngine.status(plan: plan, snapshot: snap, caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: nil, now: now)
    let five = status.windows.first { $0.kind == .fiveHour }!
    #expect(abs(five.percent! - 0.2) < 1e-9)
    #expect(five.provenance == .estimated)
    #expect(abs(status.headlinePercent! - 0.2) < 1e-9)
    #expect(status.provenance == .estimated)
}

@Test func liveValuesOverrideEstimate() {
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
    let live = LiveLimits(fiveHourPercent: 0.42, weeklyPercent: 0.10,
                          fiveHourResetsAt: now, weeklyResetsAt: now)
    let status = LimitEngine.status(plan: plan, snapshot: snapshot(), caps: .bundled,
                                    prices: .bundled, live: live,
                                    apiMonthlyBudgetUSD: nil, now: now)
    let five = status.windows.first { $0.kind == .fiveHour }!
    #expect(five.percent == 0.42)
    #expect(five.provenance == .live)
    #expect(five.resetsAt == now)
    #expect(status.provenance == .live)
    #expect(status.headlinePercent == 0.42)
}

@Test func apiUsesMonthlyBudget() {
    let plan = PlanConfig(kind: .api)
    let snap = snapshot(monthToDate: TokenTotals(output: 1_000_000),
                        monthByModel: [Rollup(key: "claude-opus-4-8",
                                              totals: TokenTotals(output: 1_000_000))]) // $25
    let status = LimitEngine.status(plan: plan, snapshot: snap, caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: 100, now: now)   // 25/100 = 0.25
    #expect(abs(status.headlinePercent! - 0.25) < 1e-6)
    #expect(abs(status.costUSD! - 25) < 1e-6)
    #expect(status.provenance == .derived)
    #expect(status.windows.first?.kind == .month)
    #expect(status.windows.first?.resetsAt != nil)
}

@Test func creditsFromGrantWhenExtraUsageEnabled() {
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x",
                          hasExtraUsageEnabled: true,
                          creditGrant: CreditGrant(available: true, amountMinorUnits: 5000,
                                                   currency: "EUR"))
    let status = LimitEngine.status(plan: plan, snapshot: snapshot(), caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: nil, now: now)
    #expect(status.credits?.enabled == true)
    #expect(status.credits?.balanceMinorUnits == 5000)
    #expect(status.credits?.currency == "EUR")
    #expect(status.credits?.provenance == .estimated)
}

@Test func liveCreditsAreBilled() {
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
    let live = LiveLimits(creditBalanceMinorUnits: 3000, creditUsedMinorUnits: 1000,
                          currency: "USD")
    let status = LimitEngine.status(plan: plan, snapshot: snapshot(), caps: .bundled,
                                    prices: .bundled, live: live,
                                    apiMonthlyBudgetUSD: nil, now: now)
    #expect(status.credits?.provenance == .billed)
    #expect(status.credits?.balanceMinorUnits == 3000)
    #expect(status.credits?.usedThisPeriodMinorUnits == 1000)
}

@Test func unknownPlanHasNoWindowsOrHeadline() {
    let status = LimitEngine.status(plan: .unknown(), snapshot: snapshot(), caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: nil, now: now)
    #expect(status.windows.isEmpty)
    #expect(status.headlinePercent == nil)
    #expect(status.credits == nil)
}

@Test func enterpriseWithoutTierHasNilPercent() {
    let plan = PlanConfig(kind: .enterprise, rateLimitTier: nil)
    let status = LimitEngine.status(plan: plan, snapshot: snapshot(), caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: nil, now: now)
    #expect(status.windows.allSatisfy { $0.percent == nil })
    #expect(status.headlinePercent == nil)
    #expect(status.provenance == .estimated)
}
