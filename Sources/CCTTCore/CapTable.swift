import Foundation

/// Estimated per-window token caps for one rate-limit tier.
public struct WindowCaps: Sendable, Equatable {
    public var fiveHourTokens: Int
    public var weeklyTokens: Int
    public init(fiveHourTokens: Int, weeklyTokens: Int) {
        self.fiveHourTokens = fiveHourTokens
        self.weeklyTokens = weeklyTokens
    }
}

/// Bundled, versioned cap table keyed by `organizationRateLimitTier`.
/// Numbers are community-calibrated estimates (Anthropic does not publish
/// token caps) and are always surfaced with `.estimated` provenance.
public struct CapTable: Sendable, Equatable {
    public let version: String
    public let caps: [String: WindowCaps]

    public init(version: String, caps: [String: WindowCaps]) {
        self.version = version; self.caps = caps
    }

    /// Exact-match lookup; `nil` for an unknown or missing tier so the engine
    /// can show "no cap" rather than a fabricated percentage.
    public func caps(forTier tier: String?) -> WindowCaps? {
        guard let tier else { return nil }
        return caps[tier]
    }

    public static let bundled = CapTable(
        version: "2026-07-08",
        caps: [
            "default_claude_pro":     WindowCaps(fiveHourTokens: 1_000_000,  weeklyTokens: 10_000_000),
            "default_claude_max_5x":  WindowCaps(fiveHourTokens: 5_000_000,  weeklyTokens: 50_000_000),
            "default_claude_max_20x": WindowCaps(fiveHourTokens: 20_000_000, weeklyTokens: 200_000_000),
        ]
    )
}
