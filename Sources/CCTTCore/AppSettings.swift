import Foundation

/// All user-configurable settings, as one Codable value. The App persists this
/// (as JSON in `UserDefaults`); Core stays pure and testable. Decoding is
/// lenient so settings written by an older build still load (absent keys take
/// their defaults).
public struct AppSettings: Sendable, Equatable, Codable {
    /// Live rate-limit fetching (Keychain + endpoint). Opt-in — off by default.
    public var liveLimitsEnabled: Bool
    /// Manual plan override; `nil` means auto-detect from `~/.claude.json`.
    public var manualPlanKind: PlanKind?
    /// API-mode monthly budget in USD (the "limit" for pay-as-you-go).
    public var apiMonthlyBudgetUSD: Double?
    /// Manual per-window token caps (enterprise / undetected tier).
    public var manualFiveHourCap: Int?
    public var manualWeeklyCap: Int?
    /// Threshold notifications. Opt-in — off by default.
    public var alertsEnabled: Bool
    public var thresholds: AlertThresholds
    /// Override for `~/.claude/projects`; `nil` uses the default path.
    public var projectsPathOverride: String?
    /// Detail tabs the user has toggled off (by stable id).
    public var hiddenTabs: Set<String>
    /// Currency code for money display.
    public var currencyCode: String
    /// Show the "% used" text next to the gauge glyph in the menu bar. When
    /// off, only the icon shows (compact). On by default.
    public var showPercentInMenuBar: Bool

    public init(liveLimitsEnabled: Bool = false,
                manualPlanKind: PlanKind? = nil,
                apiMonthlyBudgetUSD: Double? = nil,
                manualFiveHourCap: Int? = nil,
                manualWeeklyCap: Int? = nil,
                alertsEnabled: Bool = false,
                thresholds: AlertThresholds = .default,
                projectsPathOverride: String? = nil,
                hiddenTabs: Set<String> = [],
                currencyCode: String = "USD",
                showPercentInMenuBar: Bool = true) {
        self.liveLimitsEnabled = liveLimitsEnabled
        self.manualPlanKind = manualPlanKind
        self.apiMonthlyBudgetUSD = apiMonthlyBudgetUSD
        self.manualFiveHourCap = manualFiveHourCap
        self.manualWeeklyCap = manualWeeklyCap
        self.alertsEnabled = alertsEnabled
        self.thresholds = thresholds
        self.projectsPathOverride = projectsPathOverride
        self.hiddenTabs = hiddenTabs
        self.currencyCode = currencyCode
        self.showPercentInMenuBar = showPercentInMenuBar
    }

    // Lenient decoding: every field falls back to its default when absent.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        liveLimitsEnabled = try c.decodeIfPresent(Bool.self, forKey: .liveLimitsEnabled) ?? d.liveLimitsEnabled
        manualPlanKind = try c.decodeIfPresent(PlanKind.self, forKey: .manualPlanKind) ?? d.manualPlanKind
        apiMonthlyBudgetUSD = try c.decodeIfPresent(Double.self, forKey: .apiMonthlyBudgetUSD) ?? d.apiMonthlyBudgetUSD
        manualFiveHourCap = try c.decodeIfPresent(Int.self, forKey: .manualFiveHourCap) ?? d.manualFiveHourCap
        manualWeeklyCap = try c.decodeIfPresent(Int.self, forKey: .manualWeeklyCap) ?? d.manualWeeklyCap
        alertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? d.alertsEnabled
        thresholds = try c.decodeIfPresent(AlertThresholds.self, forKey: .thresholds) ?? d.thresholds
        projectsPathOverride = try c.decodeIfPresent(String.self, forKey: .projectsPathOverride) ?? d.projectsPathOverride
        hiddenTabs = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenTabs) ?? d.hiddenTabs
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? d.currencyCode
        showPercentInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showPercentInMenuBar) ?? d.showPercentInMenuBar
    }
}

/// Formats a money amount given in minor units (cents) + an ISO currency code.
/// Used for credit balances/spend (`.billed`) — distinct from derived "≈ cost".
public enum MoneyFormat {
    public static func string(minorUnits: Int?, currency: String) -> String {
        guard let minorUnits else { return "—" }
        let major = Double(minorUnits) / 100
        let amount = String(format: "%.2f", major)
        switch currency.uppercased() {
        case "USD": return "$\(amount)"
        case "EUR": return "€\(amount)"
        case "GBP": return "£\(amount)"
        default:    return "\(currency.uppercased()) \(amount)"
        }
    }
}
