import Testing
import Foundation
@testable import CCTTCore

private func line(_ s: String) -> Data { Data(s.utf8) }

@Test func parsesAssistantUsageLine() {
    let json = """
    {"type":"assistant","timestamp":"2026-07-08T19:46:01.335Z","sessionId":"s1",\
    "cwd":"/Users/x/code/CCTT","isSidechain":false,"attributionSkill":"brainstorming",\
    "attributionPlugin":"superpowers","requestId":"req_1","version":"2.1.204",\
    "gitBranch":"main","message":{"model":"claude-opus-4-8","id":"msg_1",\
    "usage":{"input_tokens":22245,"output_tokens":513,\
    "cache_creation_input_tokens":8713,"cache_read_input_tokens":18891,\
    "service_tier":"standard","server_tool_use":{"web_search_requests":2,\
    "web_fetch_requests":1}}}}
    """
    guard case let .event(e) = JSONLParser.parseLine(line(json)) else {
        Issue.record("expected .event"); return
    }
    #expect(e.model == "claude-opus-4-8")
    #expect(e.inputTokens == 22245)
    #expect(e.outputTokens == 513)
    #expect(e.cacheCreationTokens == 8713)
    #expect(e.cacheReadTokens == 18891)
    #expect(e.webSearchRequests == 2)
    #expect(e.webFetchRequests == 1)
    #expect(e.sessionId == "s1")
    #expect(e.project == "CCTT")
    #expect(e.skill == "brainstorming")
    #expect(e.plugin == "superpowers")
    #expect(e.messageId == "msg_1")
    #expect(e.requestId == "req_1")
    #expect(e.isSidechain == false)
    // Derive the expected instant via ISO8601 (no magic numbers).
    let expected = ISO8601DateFormatter().date(from: "2026-07-08T19:46:01Z")!
    #expect(abs(e.timestamp.timeIntervalSince1970 - expected.timeIntervalSince1970) < 1)
}

@Test func skipsUserLine() {
    let json = #"{"type":"user","message":{"role":"user","content":"hi"}}"#
    #expect(JSONLParser.parseLine(line(json)) == .skipped)
}

@Test func parsesAiTitleLine() {
    let json = #"{"type":"ai-title","sessionId":"s1","aiTitle":"Improve detail view perf"}"#
    #expect(JSONLParser.parseLine(line(json))
            == .sessionTitle(sessionId: "s1", title: "Improve detail view perf"))
}

@Test func skipsAiTitleLineWithoutTitleOrSession() {
    #expect(JSONLParser.parseLine(line(#"{"type":"ai-title","sessionId":"s1"}"#)) == .skipped)
    #expect(JSONLParser.parseLine(line(#"{"type":"ai-title","sessionId":"s1","aiTitle":""}"#)) == .skipped)
    #expect(JSONLParser.parseLine(line(#"{"type":"ai-title","aiTitle":"t"}"#)) == .skipped)
}

@Test func skipsAssistantLineWithoutUsage() {
    let json = #"{"type":"assistant","message":{"model":"m","id":"x"}}"#
    #expect(JSONLParser.parseLine(line(json)) == .skipped)
}

@Test func reportsMalformedJSON() {
    #expect(JSONLParser.parseLine(line("{not json")) == .malformed)
}

@Test func skipsBlankLine() {
    #expect(JSONLParser.parseLine(line("   ")) == .skipped)
}

@Test func sidechainAndMissingAttributionParse() {
    let json = """
    {"type":"assistant","timestamp":"2026-07-08T19:46:01Z","sessionId":"s2",\
    "cwd":"/tmp/proj","isSidechain":true,"message":{"model":"claude-haiku-4-5",\
    "id":"m2","usage":{"input_tokens":10,"output_tokens":5}}}
    """
    guard case let .event(e) = JSONLParser.parseLine(line(json)) else {
        Issue.record("expected .event"); return
    }
    #expect(e.isSidechain == true)
    #expect(e.skill == nil)
    #expect(e.plugin == nil)
    #expect(e.cacheReadTokens == 0)   // absent → 0
    #expect(e.serviceTier == nil)
    #expect(e.project == "proj")
}

@Test func projectNameFallsBackToRawWhenNoComponent() {
    #expect(JSONLParser.projectName(fromCwd: "") == "")
    #expect(JSONLParser.projectName(fromCwd: "/") == "/")
    #expect(JSONLParser.projectName(fromCwd: "/Users/x/code/CCTT") == "CCTT")
    #expect(JSONLParser.projectName(fromCwd: "/Users/x/code/CCTT/") == "CCTT")
}
