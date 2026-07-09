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
