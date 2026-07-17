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
            // Enterprise usage is governed by a dollar spend limit, not token
            // windows — surface that meter when a spend cap is configured.
            if plan.kind == .enterprise,
               let spend = spendLimit(plan: plan, snapshot: snapshot, prices: prices,
                                      live: live, now: now) {
                let isLive = spend.provenance == .billed
                return PlanStatus(kind: .enterprise, planLabel: plan.planLabel, windows: [],
                                  credits: nil, spendLimit: spend,
                                  costUSD: prices.costUSD(forByModel: snapshot.byModel),
                                  provenance: isLive ? .live : .estimated,
                                  liveAsOf: isLive ? live?.observedAt : nil, generatedAt: now)
            }
            // Tier cap wins; fall back to a user-entered manual cap when the
            // tier is unknown (enterprise / unrecognised tier).
            let tierCaps = caps.caps(forTier: plan.rateLimitTier) ?? manualCaps
            let isLive = live?.fiveHourPercent != nil || live?.weeklyPercent != nil
            let five = windowStatus(kind: .fiveHour, used: snapshot.fiveHour.total,
                                    cap: tierCaps?.fiveHourTokens,
                                    livePercent: live?.fiveHourPercent,
                                    liveReset: live?.fiveHourResetsAt,
                                    localReset: snapshot.fiveHourBlock?.end,
                                    duration: SessionBlocks.duration, now: now)
            let week = windowStatus(kind: .weekly, used: snapshot.weekly.total,
                                    cap: tierCaps?.weeklyTokens,
                                    livePercent: live?.weeklyPercent,
                                    liveReset: live?.weeklyResetsAt,
                                    localReset: nil,   // a rolling window has no local anchor
                                    duration: 7 * 24 * 3600, now: now)
            return PlanStatus(kind: plan.kind, planLabel: plan.planLabel,
                              windows: [five, week], credits: creditsStatus,
                              costUSD: prices.costUSD(forByModel: snapshot.byModel),
                              provenance: isLive ? .live : .estimated,
                              liveAsOf: isLive ? live?.observedAt : nil, generatedAt: now)

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

    /// `liveReset` and `localReset` are kept separate deliberately. A live response
    /// can carry a percent with no parseable `resets_at` (the decoder reads the two
    /// fields independently), and `WindowStatus` has a single provenance for the
    /// whole window — so `??`-merging them would let a `.live` window report our
    /// local block guess as a live reset time, and `Pace` would inherit that lie.
    private static func windowStatus(kind: WindowKind, used: Int, cap: Int?,
                                     livePercent: Double?, liveReset: Date?,
                                     localReset: Date?,
                                     duration: TimeInterval, now: Date) -> WindowStatus {
        let isLive = livePercent != nil
        let percent: Double? = livePercent
            ?? ((cap ?? 0) > 0 ? Double(used) / Double(cap!) : nil)
        let provenance: Provenance = isLive ? .live : .estimated
        let reset: Date? = isLive ? liveReset : localReset
        // Pace needs an anchored window end. Weekly without live has none, so pace
        // stays nil there — a rolling window's elapsed fraction is 1.0 by
        // construction, which would make the ratio meaningless.
        let pace: Pace? = {
            guard let percent, let reset else { return nil }
            return Pace.evaluate(percent: percent, windowEnd: reset, duration: duration,
                                 now: now, provenance: provenance)
        }()
        return WindowStatus(kind: kind, usedTokens: used, capTokens: cap, percent: percent,
                            resetsAt: reset, provenance: provenance, pace: pace)
    }

    /// The enterprise dollar spend limit: month-to-date derived cost (or the live
    /// billed spend, when available) against the configured cap, resetting at the
    /// next calendar month. `nil` when no dollar spend cap is configured.
    private static func spendLimit(plan: PlanConfig, snapshot: UsageSnapshot,
                                   prices: PriceTable, live: LiveLimits?,
                                   now: Date) -> SpendLimitStatus? {
        guard let cap = plan.creditGrant?.amountMinorUnits, cap > 0 else { return nil }
        let reset = nextMonthStart(after: now)
        // Prefer a real billed spend from the live endpoint when present.
        if let used = live?.creditUsedMinorUnits {
            return SpendLimitStatus(spentMinorUnits: used, capMinorUnits: cap,
                                    percent: Double(used) / Double(cap), resetsAt: reset,
                                    currency: live?.currency ?? plan.currency, provenance: .billed)
        }
        let monthCost = prices.costUSD(forByModel: snapshot.monthByModel)
        let spent = Int((monthCost * 100).rounded())
        return SpendLimitStatus(spentMinorUnits: spent, capMinorUnits: cap,
                                percent: Double(spent) / Double(cap), resetsAt: reset,
                                currency: plan.creditGrant?.currency ?? plan.currency,
                                provenance: .derived)
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
