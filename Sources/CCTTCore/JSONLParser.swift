import Foundation

/// Parses a single JSONL log line into a `UsageEvent` when it is a countable
/// assistant message carrying usage; otherwise reports skipped or malformed.
public enum JSONLParser {

    public enum ParseOutcome: Equatable {
        case event(UsageEvent)
        case sessionTitle(sessionId: String, title: String)  // Claude Code's `ai-title` line
        case skipped     // valid JSON, but not an assistant-with-usage line
        case malformed   // could not decode as JSON
    }

    // ISO8601 with and without fractional seconds; Claude Code emits both.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    public static func projectName(fromCwd cwd: String) -> String {
        let trimmed = cwd.hasSuffix("/") && cwd.count > 1
            ? String(cwd.dropLast()) : cwd
        let last = trimmed.split(separator: "/").last.map(String.init)
        return last ?? trimmed
    }

    public static func parseLine(_ data: Data) -> ParseOutcome {
        // Blank / whitespace-only lines are simply skipped.
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }) {
            return .skipped
        }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            return .malformed
        }
        // Claude Code writes a generated, human-readable session title on a dedicated
        // `ai-title` line (keyed only by sessionId — no cwd). Surface it so the UI can
        // show it in place of the raw session UUID.
        if raw.type == "ai-title", let sid = raw.sessionId,
           let title = raw.aiTitle, !title.isEmpty {
            return .sessionTitle(sessionId: sid, title: title)
        }

        guard raw.type == "assistant",
              let msg = raw.message,
              let usage = msg.usage,
              let model = msg.model,
              // A usage-bearing assistant line must have at least output tokens.
              usage.output_tokens != nil || usage.input_tokens != nil
        else { return .skipped }

        let event = UsageEvent(
            timestamp: parseDate(raw.timestamp) ?? Date(timeIntervalSince1970: 0),
            model: model,
            inputTokens: usage.input_tokens ?? 0,
            outputTokens: usage.output_tokens ?? 0,
            cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
            cacheReadTokens: usage.cache_read_input_tokens ?? 0,
            webSearchRequests: usage.server_tool_use?.web_search_requests ?? 0,
            webFetchRequests: usage.server_tool_use?.web_fetch_requests ?? 0,
            serviceTier: usage.service_tier,
            sessionId: raw.sessionId ?? "unknown",
            project: projectName(fromCwd: raw.cwd ?? ""),
            cwd: raw.cwd ?? "",
            isSidechain: raw.isSidechain ?? false,
            skill: raw.attributionSkill,
            plugin: raw.attributionPlugin,
            requestId: raw.requestId,
            messageId: msg.id,
            version: raw.version,
            gitBranch: raw.gitBranch
        )
        return .event(event)
    }

    // MARK: - Raw Codable mirror of the JSONL schema (only fields we use).

    private struct Raw: Decodable {
        let type: String?
        let timestamp: String?
        let sessionId: String?
        let cwd: String?
        let isSidechain: Bool?
        let attributionSkill: String?
        let attributionPlugin: String?
        let requestId: String?
        let version: String?
        let gitBranch: String?
        let aiTitle: String?
        let message: RawMessage?
    }
    private struct RawMessage: Decodable {
        let model: String?
        let id: String?
        let usage: RawUsage?
    }
    private struct RawUsage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
        let service_tier: String?
        let server_tool_use: RawServerToolUse?
    }
    private struct RawServerToolUse: Decodable {
        let web_search_requests: Int?
        let web_fetch_requests: Int?
    }
}
