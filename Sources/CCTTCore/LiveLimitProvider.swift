import Foundation

/// Live rate-limit values fetched from Claude Code's status endpoint.
/// Every field is optional so a partial response still degrades gracefully.
public struct LiveLimits: Sendable, Equatable {
    public var fiveHourPercent: Double?
    public var weeklyPercent: Double?
    public var fiveHourResetsAt: Date?
    public var weeklyResetsAt: Date?
    public var creditBalanceMinorUnits: Int?
    public var creditUsedMinorUnits: Int?
    public var currency: String?

    public init(fiveHourPercent: Double? = nil, weeklyPercent: Double? = nil,
                fiveHourResetsAt: Date? = nil, weeklyResetsAt: Date? = nil,
                creditBalanceMinorUnits: Int? = nil, creditUsedMinorUnits: Int? = nil,
                currency: String? = nil) {
        self.fiveHourPercent = fiveHourPercent; self.weeklyPercent = weeklyPercent
        self.fiveHourResetsAt = fiveHourResetsAt; self.weeklyResetsAt = weeklyResetsAt
        self.creditBalanceMinorUnits = creditBalanceMinorUnits
        self.creditUsedMinorUnits = creditUsedMinorUnits; self.currency = currency
    }
}

/// Single seam for all live-limit access. The whole app works without it.
public protocol LiveLimitProvider: Sendable {
    func fetch() async -> LiveLimits?
}

/// Plan-2 default: reports unavailable, so the engine uses the estimate path.
/// Replaced by a real Keychain + endpoint provider in Plan 4.
public struct UnavailableLiveLimitProvider: LiveLimitProvider {
    public init() {}
    public func fetch() async -> LiveLimits? { nil }
}

/// Test / dev provider returning a fixed value.
public struct StaticLiveLimitProvider: LiveLimitProvider {
    public let value: LiveLimits?
    public init(_ value: LiveLimits?) { self.value = value }
    public func fetch() async -> LiveLimits? { value }
}
