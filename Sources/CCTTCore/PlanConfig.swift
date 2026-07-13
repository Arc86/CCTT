import Foundation

/// The kind of Claude Code plan CCTT is observing.
public enum PlanKind: String, Sendable, Equatable, Codable {
    case subscription   // Pro / Max — rate-limited rolling windows
    case api            // pay-as-you-go — a dollar budget, not a token cap
    case enterprise     // org seat — window-based if a tier is detectable
    case unknown        // could not classify
}

/// How the active `PlanConfig` was arrived at.
public enum PlanSource: Sendable, Equatable {
    case detected   // classified from ~/.claude.json / environment
    case manual     // user override in Settings (Plan 4)
    case fallback   // ambiguous input → conservative default
}

/// Extra-usage / overage credit grant, mirrored from
/// `overageCreditGrantCache[<orgUuid>].info` in ~/.claude.json.
public struct CreditGrant: Sendable, Equatable {
    public var available: Bool
    public var eligible: Bool
    public var granted: Bool
    public var amountMinorUnits: Int?   // e.g. cents; nil when absent
    public var currency: String?

    public init(available: Bool = false, eligible: Bool = false, granted: Bool = false,
                amountMinorUnits: Int? = nil, currency: String? = nil) {
        self.available = available; self.eligible = eligible; self.granted = granted
        self.amountMinorUnits = amountMinorUnits; self.currency = currency
    }
}

/// The detected (or overridden) plan CCTT computes limits against.
public struct PlanConfig: Sendable, Equatable {
    public var kind: PlanKind
    public var rateLimitTier: String?     // organizationRateLimitTier
    public var organizationType: String?  // e.g. "claude_max"
    public var billingType: String?       // e.g. "stripe_subscription"
    public var hasExtraUsageEnabled: Bool
    public var seatTier: String?
    public var organizationRole: String?
    public var displayName: String?
    public var currency: String           // best-known currency for money display
    public var creditGrant: CreditGrant?
    public var source: PlanSource

    public init(kind: PlanKind,
                rateLimitTier: String? = nil,
                organizationType: String? = nil,
                billingType: String? = nil,
                hasExtraUsageEnabled: Bool = false,
                seatTier: String? = nil,
                organizationRole: String? = nil,
                displayName: String? = nil,
                currency: String = "USD",
                creditGrant: CreditGrant? = nil,
                source: PlanSource = .detected) {
        self.kind = kind; self.rateLimitTier = rateLimitTier
        self.organizationType = organizationType; self.billingType = billingType
        self.hasExtraUsageEnabled = hasExtraUsageEnabled; self.seatTier = seatTier
        self.organizationRole = organizationRole; self.displayName = displayName
        self.currency = currency; self.creditGrant = creditGrant; self.source = source
    }

    /// Conservative default when detection fails or is ambiguous.
    public static func unknown(source: PlanSource = .fallback) -> PlanConfig {
        PlanConfig(kind: .unknown, source: source)
    }

    /// Short, human-readable plan name for the popover header.
    public var planLabel: String {
        switch kind {
        // Enterprise is always labelled "Enterprise" — the rate-limit tier only
        // sizes token caps (which enterprise surfaces as a $ spend limit anyway),
        // so it must not masquerade as a "Max 5x" consumer plan.
        case .enterprise:
            return "Enterprise"
        case .subscription:
            switch rateLimitTier {
            case "default_claude_pro":    return "Pro"
            case "default_claude_max_5x": return "Max 5x"
            case "default_claude_max_20x": return "Max 20x"
            default:                      return organizationType ?? "Subscription"
            }
        case .api:     return "API"
        case .unknown: return "Unknown plan"
        }
    }
}
