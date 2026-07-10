import Foundation

/// One assistant message's token usage, extracted from a JSONL log line.
/// `Codable` so it can be persisted to CCTT's durable event log (`EventStore`),
/// which is what lets historical usage survive an app restart.
public struct UsageEvent: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let webSearchRequests: Int
    public let webFetchRequests: Int
    public let serviceTier: String?
    public let sessionId: String
    public let project: String       // derived from cwd (last path component)
    public let cwd: String
    public let isSidechain: Bool
    public let skill: String?        // attributionSkill
    public let plugin: String?       // attributionPlugin
    public let requestId: String?
    public let messageId: String?
    public let version: String?
    public let gitBranch: String?

    public init(timestamp: Date, model: String, inputTokens: Int, outputTokens: Int,
                cacheCreationTokens: Int, cacheReadTokens: Int, webSearchRequests: Int,
                webFetchRequests: Int, serviceTier: String?, sessionId: String,
                project: String, cwd: String, isSidechain: Bool, skill: String?,
                plugin: String?, requestId: String?, messageId: String?,
                version: String?, gitBranch: String?) {
        self.timestamp = timestamp; self.model = model
        self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens; self.cacheReadTokens = cacheReadTokens
        self.webSearchRequests = webSearchRequests; self.webFetchRequests = webFetchRequests
        self.serviceTier = serviceTier; self.sessionId = sessionId
        self.project = project; self.cwd = cwd; self.isSidechain = isSidechain
        self.skill = skill; self.plugin = plugin
        self.requestId = requestId; self.messageId = messageId
        self.version = version; self.gitBranch = gitBranch
    }

    /// Full context size sent for this message (fresh input + both cache tiers).
    public var totalContextTokens: Int {
        inputTokens + cacheReadTokens + cacheCreationTokens
    }

    /// "main" for top-level turns, "subagent" for sidechain (Task/subagent) turns.
    public var agentKind: String { isSidechain ? "subagent" : "main" }

    /// Stable identity for de-duplication; nil when the record lacks either id
    /// (such events cannot be de-duplicated and are always counted).
    public var dedupKey: String? {
        guard let requestId, let messageId else { return nil }
        return "\(requestId)|\(messageId)"
    }

    /// This event's token counts as a `TokenTotals` (eventCount = 1).
    public var totals: TokenTotals {
        TokenTotals(input: inputTokens, output: outputTokens,
                    cacheCreation: cacheCreationTokens, cacheRead: cacheReadTokens,
                    webSearch: webSearchRequests, webFetch: webFetchRequests,
                    eventCount: 1)
    }
}
