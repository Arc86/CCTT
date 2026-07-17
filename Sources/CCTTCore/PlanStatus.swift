import Foundation

/// Which limit window a `WindowStatus` describes.
public enum WindowKind: Sendable, Equatable {
    case fiveHour   // subscription rolling 5-hour window
    case weekly     // subscription rolling 7-day window
    case month      // API calendar-month budget window
}

/// One limit window's usage vs. its cap.
public struct WindowStatus: Sendable, Equatable {
    public let kind: WindowKind
    public let usedTokens: Int
    public let capTokens: Int?      // nil when no cap is known
    public let percent: Double?     // 0...1+ (fraction), nil when uncomputable
    public let resetsAt: Date?      // live reset, else the local block end (5h only)
    public let provenance: Provenance
    /// Burn rate for this window. `nil` when undefined — notably always `nil` for
    /// the weekly window without live limits, since a rolling window has no anchor.
    public let pace: Pace?

    public init(kind: WindowKind, usedTokens: Int, capTokens: Int?, percent: Double?,
                resetsAt: Date?, provenance: Provenance, pace: Pace? = nil) {
        self.kind = kind; self.usedTokens = usedTokens; self.capTokens = capTokens
        self.percent = percent; self.resetsAt = resetsAt; self.provenance = provenance
        self.pace = pace
    }
}

/// Usage-credit / extra-usage status. Rendered only when `enabled`.
public struct CreditsStatus: Sendable, Equatable {
    public let enabled: Bool
    public let balanceMinorUnits: Int?
    public let usedThisPeriodMinorUnits: Int?
    public let currency: String
    public let provenance: Provenance   // .billed (live) or .estimated (grant cache)

    public init(enabled: Bool, balanceMinorUnits: Int?, usedThisPeriodMinorUnits: Int?,
                currency: String, provenance: Provenance) {
        self.enabled = enabled; self.balanceMinorUnits = balanceMinorUnits
        self.usedThisPeriodMinorUnits = usedThisPeriodMinorUnits
        self.currency = currency; self.provenance = provenance
    }
}

/// A dollar spend limit vs. its cap — how enterprise usage is surfaced (a
/// spending budget), in place of the token 5-hour/weekly windows. Live billing
/// is `.billed`; the local-cost estimate is `.derived` (an "≈" figure).
public struct SpendLimitStatus: Sendable, Equatable {
    public let spentMinorUnits: Int
    public let capMinorUnits: Int
    public let percent: Double          // spent / cap (0…1+)
    public let resetsAt: Date?
    public let currency: String
    public let provenance: Provenance

    public init(spentMinorUnits: Int, capMinorUnits: Int, percent: Double,
                resetsAt: Date?, currency: String, provenance: Provenance) {
        self.spentMinorUnits = spentMinorUnits; self.capMinorUnits = capMinorUnits
        self.percent = percent; self.resetsAt = resetsAt
        self.currency = currency; self.provenance = provenance
    }
}

/// The computed, displayable plan status published to the UI.
public struct PlanStatus: Sendable, Equatable {
    public let kind: PlanKind
    public let planLabel: String
    public let windows: [WindowStatus]
    public let credits: CreditsStatus?
    /// Enterprise dollar spend limit; when set, the UI renders this in place of
    /// the token windows (which are then empty).
    public let spendLimit: SpendLimitStatus?
    public let costUSD: Double?        // derived "≈ cost"; nil when N/A
    public let provenance: Provenance  // headline treatment (.live/.estimated/.derived)
    /// When the live sample behind a `.live` status was actually fetched. `nil`
    /// unless this status is live-sourced. The UI compares it to "now" to render
    /// the sample's age and flag a stale-but-served live reading.
    public let liveAsOf: Date?
    public let generatedAt: Date

    public init(kind: PlanKind, planLabel: String, windows: [WindowStatus],
                credits: CreditsStatus?, spendLimit: SpendLimitStatus? = nil,
                costUSD: Double?, provenance: Provenance,
                liveAsOf: Date? = nil, generatedAt: Date) {
        self.kind = kind; self.planLabel = planLabel; self.windows = windows
        self.credits = credits; self.spendLimit = spendLimit; self.costUSD = costUSD
        self.provenance = provenance; self.liveAsOf = liveAsOf
        self.generatedAt = generatedAt
    }

    /// The most-constraining percentage driving the menu-bar headline: the token
    /// windows (spec: `max(5h%, weekly%)`) or, for enterprise, the spend limit.
    public var headlinePercent: Double? {
        (windows.compactMap(\.percent) + [spendLimit?.percent].compactMap { $0 }).max()
    }

    public static func empty(now: Date) -> PlanStatus {
        PlanStatus(kind: .unknown, planLabel: "Unknown plan", windows: [],
                   credits: nil, costUSD: nil, provenance: .estimated, generatedAt: now)
    }
}
