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
    private let apiMonthlyBudgetUSD: Double?
    private let clock: @Sendable () -> Date

    public init(configURL: URL,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                caps: CapTable = .bundled,
                prices: PriceTable = .bundled,
                provider: LiveLimitProvider = UnavailableLiveLimitProvider(),
                apiMonthlyBudgetUSD: Double? = nil,
                clock: @escaping @Sendable () -> Date) {
        self.configURL = configURL
        self.environment = environment
        self.caps = caps
        self.prices = prices
        self.provider = provider
        self.apiMonthlyBudgetUSD = apiMonthlyBudgetUSD
        self.clock = clock
        self.plan = .unknown(source: .fallback)
        self.status = .empty(now: clock())
    }

    /// Re-detect the plan, fetch live limits, and recompute the status.
    public func refresh(snapshot: UsageSnapshot) async {
        let detected = PlanDetector.detect(configURL: configURL, environment: environment)
        let live = await provider.fetch()
        let newStatus = LimitEngine.status(plan: detected, snapshot: snapshot, caps: caps,
                                           prices: prices, live: live,
                                           apiMonthlyBudgetUSD: apiMonthlyBudgetUSD,
                                           now: clock())
        plan = detected
        status = newStatus
    }
}
