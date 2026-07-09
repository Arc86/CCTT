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
    public let resetsAt: Date?      // known only on the live path
    public let provenance: Provenance

    public init(kind: WindowKind, usedTokens: Int, capTokens: Int?, percent: Double?,
                resetsAt: Date?, provenance: Provenance) {
        self.kind = kind; self.usedTokens = usedTokens; self.capTokens = capTokens
        self.percent = percent; self.resetsAt = resetsAt; self.provenance = provenance
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

/// The computed, displayable plan status published to the UI.
public struct PlanStatus: Sendable, Equatable {
    public let kind: PlanKind
    public let planLabel: String
    public let windows: [WindowStatus]
    public let credits: CreditsStatus?
    public let costUSD: Double?        // derived "≈ cost"; nil when N/A
    public let provenance: Provenance  // headline treatment (.live/.estimated/.derived)
    public let generatedAt: Date

    public init(kind: PlanKind, planLabel: String, windows: [WindowStatus],
                credits: CreditsStatus?, costUSD: Double?, provenance: Provenance,
                generatedAt: Date) {
        self.kind = kind; self.planLabel = planLabel; self.windows = windows
        self.credits = credits; self.costUSD = costUSD
        self.provenance = provenance; self.generatedAt = generatedAt
    }

    /// The most-constraining window percentage (spec: `max(5h%, weekly%)`).
    public var headlinePercent: Double? { windows.compactMap(\.percent).max() }

    public static func empty(now: Date) -> PlanStatus {
        PlanStatus(kind: .unknown, planLabel: "Unknown plan", windows: [],
                   credits: nil, costUSD: nil, provenance: .estimated, generatedAt: now)
    }
}
