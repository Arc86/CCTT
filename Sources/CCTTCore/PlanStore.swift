import Foundation
import Observation

/// Owns the detected plan and the published, computed `PlanStatus`.
/// Detection and computation are pure; only the two published values live here.
@MainActor
@Observable
public final class PlanStore {
    public private(set) var plan: PlanConfig
    public private(set) var status: PlanStatus

    private let configURL: URL
    private let environment: [String: String]
    private let caps: CapTable
    private let prices: PriceTable
    private let provider: LiveLimitProvider
    private let settingsProvider: @Sendable () -> AppSettings
    private let clock: @Sendable () -> Date

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
        let live = await provider.fetch()
        let newStatus = LimitEngine.status(plan: detected, snapshot: snapshot, caps: caps,
                                           prices: prices, live: live,
                                           apiMonthlyBudgetUSD: settings.apiMonthlyBudgetUSD,
                                           manualCaps: manualCaps(from: settings),
                                           now: clock())
        plan = detected
        status = newStatus
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
