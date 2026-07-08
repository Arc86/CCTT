import Foundation
@testable import CCTTCore

extension UsageEvent {
    /// Test-only builder with sensible defaults; override only what a test cares about.
    static func fixture(
        timestamp: Date = Date(timeIntervalSince1970: 1_780_000_000),
        model: String = "claude-opus-4-8",
        input: Int = 100, output: Int = 50,
        cacheCreation: Int = 0, cacheRead: Int = 0,
        webSearch: Int = 0, webFetch: Int = 0,
        serviceTier: String? = "standard",
        sessionId: String = "sess-1",
        project: String = "CCTT",
        cwd: String = "/Users/x/code/CCTT",
        isSidechain: Bool = false,
        skill: String? = nil, plugin: String? = nil,
        requestId: String? = "req-1", messageId: String? = "msg-1",
        version: String? = "2.1.204", gitBranch: String? = "main"
    ) -> UsageEvent {
        UsageEvent(timestamp: timestamp, model: model, inputTokens: input,
                   outputTokens: output, cacheCreationTokens: cacheCreation,
                   cacheReadTokens: cacheRead, webSearchRequests: webSearch,
                   webFetchRequests: webFetch, serviceTier: serviceTier,
                   sessionId: sessionId, project: project, cwd: cwd,
                   isSidechain: isSidechain, skill: skill, plugin: plugin,
                   requestId: requestId, messageId: messageId,
                   version: version, gitBranch: gitBranch)
    }
}
