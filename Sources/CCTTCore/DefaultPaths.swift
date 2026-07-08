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
}
