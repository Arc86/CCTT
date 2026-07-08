import Testing
import Foundation
@testable import CCTTCore

private struct Harness {
    let projectsDir: URL
    let cacheURL: URL
    init() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cctt-ingest-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        projectsDir = base.appendingPathComponent("projects")
        try! FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        cacheURL = base.appendingPathComponent("offsets.json")
    }
    func write(_ name: String, _ contents: String) {
        let dir = projectsDir.appendingPathComponent("proj-a")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! Data(contents.utf8).write(to: dir.appendingPathComponent(name))
    }
    func append(_ name: String, _ contents: String) {
        let url = projectsDir.appendingPathComponent("proj-a").appendingPathComponent(name)
        let h = try! FileHandle(forWritingTo: url)
        h.seekToEndOfFile(); h.write(Data(contents.utf8)); try! h.close()
    }
    func ingestor() -> Ingestor { Ingestor(projectsDir: projectsDir, cacheURL: cacheURL) }
}

private func assistantLine(_ model: String, out: Int, req: String, msg: String) -> String {
    """
    {"type":"assistant","timestamp":"2026-07-08T19:46:01Z","sessionId":"s1",\
    "cwd":"/Users/x/code/CCTT","message":{"model":"\(model)","id":"\(msg)",\
    "usage":{"input_tokens":100,"output_tokens":\(out)}}}
    """
}

@Test func parsesAllEventsOnFirstScan() {
    let h = Harness()
    h.write("s.jsonl",
        assistantLine("claude-opus-4-8", out: 10, req: "r1", msg: "m1") + "\n" +
        assistantLine("claude-haiku-4-5", out: 20, req: "r2", msg: "m2") + "\n")
    let result = h.ingestor().scan()
    #expect(result.events.count == 2)
    #expect(result.parseErrors == 0)
}

@Test func secondScanWithNoChangesReturnsNothing() {
    let h = Harness()
    h.write("s.jsonl", assistantLine("m", out: 10, req: "r1", msg: "m1") + "\n")
    _ = h.ingestor().scan()
    let again = h.ingestor().scan()   // fresh ingestor, same cache file
    #expect(again.events.isEmpty)
}

@Test func appendedLinesYieldOnlyNewEvents() {
    let h = Harness()
    h.write("s.jsonl", assistantLine("m", out: 10, req: "r1", msg: "m1") + "\n")
    _ = h.ingestor().scan()
    h.append("s.jsonl", assistantLine("m", out: 20, req: "r2", msg: "m2") + "\n")
    let result = h.ingestor().scan()
    #expect(result.events.count == 1)
    #expect(result.events.first?.outputTokens == 20)
}

@Test func partialTrailingLineIsNotParsedUntilComplete() {
    let h = Harness()
    let full = assistantLine("m", out: 10, req: "r1", msg: "m1")
    h.write("s.jsonl", full + "\n" + assistantLine("m", out: 20, req: "r2", msg: "m2"))
    // no trailing newline on the 2nd line
    let first = h.ingestor().scan()
    #expect(first.events.count == 1)          // only the completed line
    h.append("s.jsonl", "\n")                  // complete the 2nd line
    let second = h.ingestor().scan()
    #expect(second.events.count == 1)          // now the 2nd line parses
    #expect(second.events.first?.outputTokens == 20)
}

@Test func truncationCausesFullReread() {
    let h = Harness()
    h.write("s.jsonl", assistantLine("m", out: 10, req: "r1", msg: "m1") + "\n")
    _ = h.ingestor().scan()
    // Overwrite (truncate) with a different single line.
    h.write("s.jsonl", assistantLine("m", out: 99, req: "r9", msg: "m9") + "\n")
    let result = h.ingestor().scan()
    #expect(result.events.count == 1)
    #expect(result.events.first?.outputTokens == 99)
}

@Test func malformedLinesAreCountedNotFatal() {
    let h = Harness()
    h.write("s.jsonl",
        "{broken\n" +
        assistantLine("m", out: 10, req: "r1", msg: "m1") + "\n")
    let result = h.ingestor().scan()
    #expect(result.events.count == 1)
    #expect(result.parseErrors == 1)
}
