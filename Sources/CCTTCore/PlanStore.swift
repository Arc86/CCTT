import Foundation
import Observation

/// Owns the detected plan and the published, computed `PlanStatus`.
/// Detection and computation are pure; only the two published values live here.
@MainActor
@Observable
public final class PlanStore {
    public private(set) var plan: PlanConfig
    public private(set) var status: PlanStatus
    /// Seconds the app should wait before calling `refresh` again. Driven by
    /// `PollSchedule`, so a throttled endpoint is polled less, not more.
    public private(set) var nextPollInterval: TimeInterval = PollSchedule.base

    private let configURL: URL
    private let environment: [String: String]
    private let caps: CapTable
    private let prices: PriceTable
    private let provider: LiveLimitProvider
    private let settingsProvider: @Sendable () -> AppSettings
    private let clock: @Sendable () -> Date
    private var schedule = PollSchedule()

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
        let result = await provider.fetch()
        let now = clock()
        schedule = schedule.next(after: result.outcome, now: now)
        nextPollInterval = schedule.interval
        let newStatus = LimitEngine.status(plan: detected, snapshot: snapshot, caps: caps,
                                           prices: prices, live: result.limits,
                                           apiMonthlyBudgetUSD: settings.apiMonthlyBudgetUSD,
                                           manualCaps: manualCaps(from: settings),
                                           liveHealth: Self.health(for: result.outcome),
                                           now: now)
        plan = detected
        status = newStatus
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
