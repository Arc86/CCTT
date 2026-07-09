import Foundation

public enum DefaultPaths {
    /// `~/.claude/projects` — where Claude Code writes JSONL session logs.
    public static var projectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// `~/Library/Application Support/CCTT/offsets.json` — CCTT's own cache.
    public static var offsetCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        return base.appendingPathComponent("CCTT/offsets.json")
    }

    /// Compact human-readable token magnitude: 999 → "999", 12_345 → "12.3K".
    public static func formatTokens(_ n: Int) -> String {
        let value = Double(n)
        switch n {
        case ..<1_000:      return "\(n)"
        case ..<1_000_000:  return String(format: "%.1fK", value / 1_000)
        default:            return String(format: "%.1fM", value / 1_000_000)
        }
    }

    /// Compact derived-cost money string: 0 → "$0", 1.234 → "$1.23", 12_300 → "$12.3K".
    /// Under $10 shows cents; then whole dollars; then K/M magnitudes.
    public static func formatUSD(_ v: Double) -> String {
        if v == 0 { return "$0" }
        switch abs(v) {
        case ..<10:        return String(format: "$%.2f", v)
        case ..<1_000:     return String(format: "$%.0f", v)
        case ..<1_000_000: return String(format: "$%.1fK", v / 1_000)
        default:           return String(format: "$%.1fM", v / 1_000_000)
        }
    }

    /// Render a bucket in the user's chosen unit: measured tokens or derived ≈$.
    public static func formatValue(totals: TokenTotals, costUSD: Double, unit: DisplayUnit) -> String {
        switch unit {
        case .tokens:  return formatTokens(totals.total)
        case .dollars: return formatUSD(costUSD)
        }
    }

    /// `~/.claude.json` — Claude Code's account/config file.
    public static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
    }

    /// Menu-bar headline: "68%" (live/derived) or "~68%" (estimated). Falls back
    /// to a compact token total when no limit percentage is available.
    public static func formatPercent(_ status: PlanStatus, fallbackTokens: Int) -> String {
        guard let p = status.headlinePercent else { return formatTokens(fallbackTokens) }
        let pct = Int((max(0, p) * 100).rounded())
        let prefix = status.provenance == .estimated ? "~" : ""
        return "\(prefix)\(pct)%"
    }
}
