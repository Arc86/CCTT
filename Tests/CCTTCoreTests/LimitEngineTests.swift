import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

private func snapshot(fiveHour: TokenTotals = .zero, fiveHourBlock: SessionBlock? = nil,
                      weekly: TokenTotals = .zero,
                      monthToDate: TokenTotals = .zero, byModel: [Rollup] = [],
                      monthByModel: [Rollup] = []) -> UsageSnapshot {
    UsageSnapshot(overall: .zero, byProject: [], byModel: byModel, bySession: [],
                  byAgentKind: [], bySkill: [], byPlugin: [],
                  fiveHour: fiveHour, fiveHourBlock: fiveHourBlock,
                  weekly: weekly, monthToDate: monthToDate,
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
    #expect(status.liveAsOf == nil)   // no observedAt on a hand-built sample
}

/// A stale-but-served live sample carries its age forward so the UI can label
/// it ("Live · 12m ago") rather than presenting frozen data as current.
@Test func liveAsOfCarriesTheSampleAge() {
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
    let observed = now.addingTimeInterval(-720)
    let live = LiveLimits(fiveHourPercent: 0.42, observedAt: observed)
    let status = LimitEngine.status(plan: plan, snapshot: snapshot(), caps: .bundled,
                                    prices: .bundled, live: live,
                                    apiMonthlyBudgetUSD: nil, now: now)
    #expect(status.provenance == .live)
    #expect(status.liveAsOf == observed)
}

/// With no live sample the estimate path carries no live timestamp.
@Test func estimatedStatusHasNoLiveAsOf() {
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
    let status = LimitEngine.status(plan: plan, snapshot: snapshot(), caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: nil, now: now)
    #expect(status.provenance == .estimated)
    #expect(status.liveAsOf == nil)
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

/// Enterprise with a configured dollar spend cap surfaces a spend-limit meter
/// (derived month-to-date cost ÷ cap) in place of the token windows, and the
/// credits line is suppressed as the same $70 is now the spend limit.
@Test func enterpriseWithSpendCapShowsSpendLimit() {
    let plan = PlanConfig(kind: .enterprise, rateLimitTier: "default_claude_max_5x",
                          hasExtraUsageEnabled: true,
                          creditGrant: CreditGrant(available: true, amountMinorUnits: 7000,
                                                   currency: "USD"))
    // Month-to-date: 468k opus output tokens → $11.70 derived.
    let snap = snapshot(monthByModel: [Rollup(key: "claude-opus-4-8[1m]",
                                              totals: TokenTotals(output: 468_000))])
    let status = LimitEngine.status(plan: plan, snapshot: snap, caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: nil, now: now)
    let spend = status.spendLimit!
    #expect(spend.spentMinorUnits == 1170)          // $11.70
    #expect(spend.capMinorUnits == 7000)            // $70.00
    #expect(abs(spend.percent - 1170.0 / 7000.0) < 1e-9)
    #expect(spend.currency == "USD")
    #expect(spend.provenance == .derived)
    #expect(spend.resetsAt != nil)
    #expect(status.windows.isEmpty)                 // replaces token windows
    #expect(status.credits == nil)                  // not duplicated as credits
    #expect(abs(status.headlinePercent! - 1170.0 / 7000.0) < 1e-9)
    #expect(status.provenance == .estimated)
}

/// Enterprise with no configured spend cap keeps the token-window behavior.
@Test func enterpriseWithoutSpendCapKeepsTokenWindows() {
    let plan = PlanConfig(kind: .enterprise, rateLimitTier: "default_claude_max_5x")
    let snap = snapshot(fiveHour: TokenTotals(input: 1_000_000))
    let status = LimitEngine.status(plan: plan, snapshot: snap, caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: nil, now: now)
    #expect(status.spendLimit == nil)
    #expect(!status.windows.isEmpty)
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

// MARK: - Local resetsAt on the estimated path

@Test func estimatedFiveHourResetsAtComesFromTheOpenBlock() {
    let start = now.addingTimeInterval(-3600)          // block opened an hour ago
    let block = SessionBlock(start: start, end: start.addingTimeInterval(5 * 3600),
                             totals: TokenTotals(input: 1_000_000))
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
    let status = LimitEngine.status(
        plan: plan,
        snapshot: snapshot(fiveHour: block.totals, fiveHourBlock: block),
        caps: .bundled, prices: .bundled, live: nil,
        apiMonthlyBudgetUSD: nil, now: now)
    let five = status.windows.first { $0.kind == .fiveHour }!
    // Previously nil on the estimated path — estimate-only users had no countdown.
    #expect(five.resetsAt == start.addingTimeInterval(5 * 3600))
    #expect(five.provenance == .estimated)
}

@Test func liveFiveHourResetsAtWinsOverTheLocalBlock() {
    let start = now.addingTimeInterval(-3600)
    let liveReset = now.addingTimeInterval(2 * 3600)   // deliberately != block end
    let block = SessionBlock(start: start, end: start.addingTimeInterval(5 * 3600),
                             totals: TokenTotals(input: 1_000_000))
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
    let status = LimitEngine.status(
        plan: plan,
        snapshot: snapshot(fiveHour: block.totals, fiveHourBlock: block),
        caps: .bundled, prices: .bundled,
        live: LiveLimits(fiveHourPercent: 0.4, fiveHourResetsAt: liveReset),
        apiMonthlyBudgetUSD: nil, now: now)
    let five = status.windows.first { $0.kind == .fiveHour }!
    #expect(five.resetsAt == liveReset)
    #expect(five.provenance == .live)
}

@Test func liveWindowNeverBorrowsTheLocalBlockEndAsItsReset() {
    // The endpoint can return a percent with no parseable resets_at (the decoder
    // reads the two fields independently). Filling the gap from our local block
    // while labelling the window .live would report a guess as live data.
    let start = now.addingTimeInterval(-3600)
    let block = SessionBlock(start: start, end: start.addingTimeInterval(5 * 3600),
                             totals: TokenTotals(input: 1_000_000))
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
    let status = LimitEngine.status(
        plan: plan,
        snapshot: snapshot(fiveHour: block.totals, fiveHourBlock: block),
        caps: .bundled, prices: .bundled,
        live: LiveLimits(fiveHourPercent: 0.4, fiveHourResetsAt: nil),
        apiMonthlyBudgetUSD: nil, now: now)
    let five = status.windows.first { $0.kind == .fiveHour }!
    #expect(five.provenance == .live)
    #expect(five.resetsAt == nil)      // NOT block.end
}

// MARK: - Pace attachment

@Test func weeklyPaceIsNilWithoutLiveBecauseTheWindowIsRolling() {
    // A rolling window's elapsed fraction is 1.0 by construction, so a ratio would
    // be meaningless. nil is the honest answer.
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
    let status = LimitEngine.status(
        plan: plan,
        snapshot: snapshot(weekly: TokenTotals(input: 5_000_000)),
        caps: .bundled, prices: .bundled, live: nil,
        apiMonthlyBudgetUSD: nil, now: now)
    #expect(status.windows.first { $0.kind == .weekly }?.pace == nil)
}

@Test func fiveHourPaceIsComputedFromTheLocalBlockWithoutLive() {
    // The estimate-only path gets pacing too, because the block supplies an anchor.
    let start = now.addingTimeInterval(-2.5 * 3600)   // halfway through the block
    let block = SessionBlock(start: start, end: start.addingTimeInterval(5 * 3600),
                             totals: TokenTotals(input: 3_000_000))  // 60% of the 5M cap
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
    let status = LimitEngine.status(
        plan: plan,
        snapshot: snapshot(fiveHour: block.totals, fiveHourBlock: block),
        caps: .bundled, prices: .bundled, live: nil,
        apiMonthlyBudgetUSD: nil, now: now)
    let pace = status.windows.first { $0.kind == .fiveHour }?.pace
    #expect(pace?.status == .willExceed)          // 60% used at 50% elapsed → ratio 1.2
    #expect(pace?.provenance == .estimated)       // inherited, never invented
}

// MARK: - liveHealth forwarding
//
// `liveHealth` is orthogonal to the window/spend computation below it — these
// tests exist only to pin that every one of the four `PlanStatus(...)` return
// sites actually forwards the parameter instead of dropping it on the floor.

@Test func liveHealthForwardsOnTheSubscriptionWindowsPath() {
    let plan = PlanConfig(kind: .subscription, rateLimitTier: "default_claude_max_5x")
    let status = LimitEngine.status(plan: plan, snapshot: snapshot(), caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: nil, liveHealth: .degraded, now: now)
    #expect(status.liveHealth == .degraded)
}

@Test func liveHealthForwardsOnTheEnterpriseSpendLimitPath() {
    let plan = PlanConfig(kind: .enterprise, rateLimitTier: "default_claude_max_5x",
                          creditGrant: CreditGrant(available: true, amountMinorUnits: 7000,
                                                   currency: "USD"))
    let status = LimitEngine.status(plan: plan, snapshot: snapshot(), caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: nil, liveHealth: .needsReauth, now: now)
    #expect(status.spendLimit != nil)
    #expect(status.liveHealth == .needsReauth)
}

@Test func liveHealthForwardsOnTheApiPath() {
    let plan = PlanConfig(kind: .api)
    let status = LimitEngine.status(plan: plan, snapshot: snapshot(), caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: nil,
                                    liveHealth: .rateLimited(until: nil), now: now)
    #expect(status.liveHealth == .rateLimited(until: nil))
}

@Test func liveHealthForwardsOnTheUnknownPath() {
    let status = LimitEngine.status(plan: .unknown(), snapshot: snapshot(), caps: .bundled,
                                    prices: .bundled, live: nil,
                                    apiMonthlyBudgetUSD: nil, liveHealth: .ok, now: now)
    #expect(status.liveHealth == .ok)
}
