import Foundation
import Observation

/// Owns the detected plan and the published, computed `PlanStatus`.
/// Detection and computation are pure; only the two published values live here.
@MainActor
@Observable
public final class PlanStore {
    public private(set) var plan: PlanConfig
    public private(set) var status: PlanStatus
    /// The interval `PollSchedule` currently prescribes before the next live
    /// *fetch* is allowed. Does **not** drive the app's refresh-loop cadence —
    /// that tick is fixed (see `CCTTApp`'s `.task`, which also runs local
    /// ingest, alerts, and export and must never stall on a throttled
    /// endpoint). This only gates whether `refresh()` calls `provider.fetch()`
    /// or reuses the last-held live reading. Published for visibility/tests.
    public private(set) var nextPollInterval: TimeInterval = PollSchedule.base

    private let configURL: URL
    private let environment: [String: String]
    private let caps: CapTable
    private let prices: PriceTable
    private let provider: LiveLimitProvider
    private let settingsProvider: @Sendable () -> AppSettings
    private let clock: @Sendable () -> Date
    private var schedule = PollSchedule()
    /// When the next `provider.fetch()` is allowed. `nil` means always fetch —
    /// true for the very first `refresh()`, and whenever the last outcome was
    /// `.disabled` (there is nothing to back off from, so live must keep
    /// recomputing normally on every tick).
    private var nextFetchAt: Date?
    /// The most recent fetch result, held so a gated (skipped) `refresh` can
    /// still recompute a status — reusing the same reading and outcome rather
    /// than inventing a new one, so provenance/`liveAsOf` never change on a skip.
    private var lastFetchResult: LiveFetchResult = .disabled

    public init(configURL: URL,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                caps: CapTable = .bundled,
                prices: PriceTable = .bundled,
                provider: LiveLimitProvider = UnavailableLiveLimitProvider(),
                settingsProvider: @escaping @Sendable () -> AppSettings = { AppSettings() },
                clock: @escaping @Sendable () -> Date) {
        self.configURL = configURL
        self.environment = environment
        self.caps = caps
        self.prices = prices
        self.provider = provider
        self.settingsProvider = settingsProvider
        self.clock = clock
        self.plan = .unknown(source: .fallback)
        self.status = .empty(now: clock())
    }

    /// Re-detect the plan, fetch live limits, and recompute the status. User
    /// settings (manual plan override, API budget, manual caps) are applied.
    public func refresh(snapshot: UsageSnapshot) async {
        let settings = settingsProvider()
        let detected = applyOverride(to: PlanDetector.detect(configURL: configURL,
                                                             environment: environment),
                                     settings: settings)
        let now = clock()
        let result = await fetchIfDue(now: now)
        let newStatus = LimitEngine.status(plan: detected, snapshot: snapshot, caps: caps,
                                           prices: prices, live: result.limits,
                                           apiMonthlyBudgetUSD: settings.apiMonthlyBudgetUSD,
                                           manualCaps: manualCaps(from: settings),
                                           liveHealth: Self.health(for: result.outcome),
                                           now: now)
        plan = detected
        status = newStatus
    }

    /// Clears the fetch throttle so the very next `refresh` is guaranteed to
    /// call `provider.fetch()`, regardless of an in-flight backoff. For a
    /// *user-initiated* retry (the Live-limits toggle): a direct request must
    /// never be silently swallowed by backoff meant for background polling —
    /// the Keychain prompt has to appear on the click, not up to `PollSchedule`'s
    /// cap later.
    public func resetFetchThrottle() {
        nextFetchAt = nil
    }

    /// Calls `provider.fetch()` only when `PollSchedule` allows it; otherwise
    /// reuses the last-held result untouched. This is the fetch-level gate
    /// `PollSchedule` was designed for — a throttled endpoint must stop being
    /// hit, but `refresh` itself keeps running on the app's fixed cadence so
    /// local ingest, alerts, and export are never held hostage to the network.
    private func fetchIfDue(now: Date) async -> LiveFetchResult {
        if let nextFetchAt, now < nextFetchAt {
            return lastFetchResult
        }
        let result = await provider.fetch()
        schedule = schedule.next(after: result.outcome, now: now)
        nextPollInterval = schedule.interval
        lastFetchResult = result
        // `.disabled` must never throttle: there is nothing to back off from,
        // and the very next refresh should still consult the provider (a
        // no-cost no-op while live is off) rather than serve a stale skip.
        nextFetchAt = result.outcome == .disabled ? nil : now.addingTimeInterval(schedule.interval)
        return result
    }

    /// Live health is `nil` when the path is switched off — there is nothing to report.
    private static func health(for outcome: LiveFetchOutcome) -> LiveHealth? {
        switch outcome {
        case .disabled:                return nil
        case .success:                 return .ok
        case .rateLimited(let until):  return .rateLimited(until: until)
        case .unauthorized:            return .needsReauth
        case .transient, .malformed:   return .degraded
        }
    }

    /// Applies a user's manual plan-kind override to the detected config.
    private func applyOverride(to detected: PlanConfig, settings: AppSettings) -> PlanConfig {
        guard let kind = settings.manualPlanKind, kind != detected.kind else { return detected }
        var overridden = detected
        overridden.kind = kind
        overridden.source = .manual
        return overridden
    }

    /// A manual per-window cap, only when both halves are provided.
    private func manualCaps(from settings: AppSettings) -> WindowCaps? {
        guard let five = settings.manualFiveHourCap,
              let week = settings.manualWeeklyCap else { return nil }
        return WindowCaps(fiveHourTokens: five, weeklyTokens: week)
    }
}
