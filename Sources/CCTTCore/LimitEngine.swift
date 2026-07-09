import Foundation

/// Combines a detected plan, aggregated usage, and (optional) live limits into
/// a displayable `PlanStatus`. Pure: all time and network inputs are injected.
public enum LimitEngine {

    public static func status(
        plan: PlanConfig,
        snapshot: UsageSnapshot,
        caps: CapTable,
        prices: PriceTable,
        live: LiveLimits?,
        apiMonthlyBudgetUSD: Double?,
        manualCaps: WindowCaps? = nil,
        now: Date
    ) -> PlanStatus {
        let creditsStatus = credits(plan: plan, live: live)

        switch plan.kind {
        case .subscription, .enterprise:
            // Tier cap wins; fall back to a user-entered manual cap when the
            // tier is unknown (enterprise / unrecognised tier).
            let tierCaps = caps.caps(forTier: plan.rateLimitTier) ?? manualCaps
            let isLive = live?.fiveHourPercent != nil || live?.weeklyPercent != nil
            let five = windowStatus(kind: .fiveHour, used: snapshot.fiveHour.total,
                                    cap: tierCaps?.fiveHourTokens,
                                    livePercent: live?.fiveHourPercent,
                                    reset: live?.fiveHourResetsAt)
            let week = windowStatus(kind: .weekly, used: snapshot.weekly.total,
                                    cap: tierCaps?.weeklyTokens,
                                    livePercent: live?.weeklyPercent,
                                    reset: live?.weeklyResetsAt)
            return PlanStatus(kind: plan.kind, planLabel: plan.planLabel,
                              windows: [five, week], credits: creditsStatus,
                              costUSD: prices.costUSD(forByModel: snapshot.byModel),
                              provenance: isLive ? .live : .estimated, generatedAt: now)

        case .api:
            let monthCost = prices.costUSD(forByModel: snapshot.monthByModel)
            let percent: Double? = {
                guard let budget = apiMonthlyBudgetUSD, budget > 0 else { return nil }
                return monthCost / budget
            }()
            let window = WindowStatus(kind: .month, usedTokens: snapshot.monthToDate.total,
                                      capTokens: nil, percent: percent,
                                      resetsAt: nextMonthStart(after: now), provenance: .derived)
            return PlanStatus(kind: .api, planLabel: plan.planLabel, windows: [window],
                              credits: creditsStatus, costUSD: monthCost,
                              provenance: .derived, generatedAt: now)

        case .unknown:
            return PlanStatus(kind: .unknown, planLabel: plan.planLabel, windows: [],
                              credits: creditsStatus,
                              costUSD: prices.costUSD(forByModel: snapshot.byModel),
                              provenance: .estimated, generatedAt: now)
        }
    }

    private static func windowStatus(kind: WindowKind, used: Int, cap: Int?,
                                     livePercent: Double?, reset: Date?) -> WindowStatus {
        if let livePercent {
            return WindowStatus(kind: kind, usedTokens: used, capTokens: cap,
                                percent: livePercent, resetsAt: reset, provenance: .live)
        }
        let percent: Double? = (cap ?? 0) > 0 ? Double(used) / Double(cap!) : nil
        return WindowStatus(kind: kind, usedTokens: used, capTokens: cap,
                            percent: percent, resetsAt: nil, provenance: .estimated)
    }

    private static func credits(plan: PlanConfig, live: LiveLimits?) -> CreditsStatus? {
        let liveHasCredits = live?.creditBalanceMinorUnits != nil
            || live?.creditUsedMinorUnits != nil
        guard plan.hasExtraUsageEnabled || liveHasCredits else { return nil }
        if liveHasCredits {
            return CreditsStatus(enabled: true, balanceMinorUnits: live?.creditBalanceMinorUnits,
                                 usedThisPeriodMinorUnits: live?.creditUsedMinorUnits,
                                 currency: live?.currency ?? plan.currency, provenance: .billed)
        }
        return CreditsStatus(enabled: true, balanceMinorUnits: plan.creditGrant?.amountMinorUnits,
                             usedThisPeriodMinorUnits: nil,
                             currency: plan.creditGrant?.currency ?? plan.currency,
                             provenance: .estimated)
    }

    private static func nextMonthStart(after now: Date) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: now))
        else { return nil }
        return cal.date(byAdding: .month, value: 1, to: start)
    }
}
