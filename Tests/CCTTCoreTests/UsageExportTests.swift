import Testing
import Foundation
@testable import CCTTCore

private let exportNow = Date(timeIntervalSince1970: 1_784_278_800)   // 2026-07-17T09:00:00Z

private func sampleStatus() -> PlanStatus {
    let reset = exportNow.addingTimeInterval(3 * 3600)
    let pace = Pace(ratio: 1.4, status: .willExceed,
                    exhaustsAt: exportNow.addingTimeInterval(3600), provenance: .live)
    let five = WindowStatus(kind: .fiveHour, usedTokens: 8_123_456, capTokens: 12_000_000,
                            percent: 0.68, resetsAt: reset, provenance: .live, pace: pace)
    return PlanStatus(kind: .subscription, planLabel: "Max 20x", windows: [five],
                      credits: nil, costUSD: 12.5, provenance: .live,
                      liveAsOf: exportNow, liveHealth: .ok, generatedAt: exportNow)
}

private func decode(_ data: Data) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

@Test func encodesTheVersionedEnvelope() throws {
    let json = try decode(try UsageExport.encode(sampleStatus()))
    #expect(json["schemaVersion"] as? Int == UsageExport.schemaVersion)
    #expect(json["generatedAt"] as? String == "2026-07-17T09:00:00Z")
    #expect(json["headlinePercent"] as? Double == 0.68)
    #expect(json["provenance"] as? String == "live")
    let plan = json["plan"] as! [String: Any]
    #expect(plan["label"] as? String == "Max 20x")
    #expect(plan["kind"] as? String == "subscription")
}

@Test func encodesAWindowWithItsPace() throws {
    let json = try decode(try UsageExport.encode(sampleStatus()))
    let windows = json["windows"] as! [[String: Any]]
    #expect(windows.count == 1)
    let w = windows[0]
    #expect(w["kind"] as? String == "fiveHour")
    #expect(w["percent"] as? Double == 0.68)
    #expect(w["usedTokens"] as? Int == 8_123_456)
    #expect(w["capTokens"] as? Int == 12_000_000)
    #expect(w["provenance"] as? String == "live")
    #expect(w["resetsAt"] as? String == "2026-07-17T12:00:00Z")
    let pace = w["pace"] as! [String: Any]
    #expect(pace["ratio"] as? Double == 1.4)
    #expect(pace["status"] as? String == "willExceed")
    #expect(pace["exhaustsAt"] as? String == "2026-07-17T10:00:00Z")
}

@Test func omitsPaceWhenAbsent() throws {
    let w = WindowStatus(kind: .weekly, usedTokens: 1, capTokens: 2, percent: 0.5,
                         resetsAt: nil, provenance: .estimated, pace: nil)
    let status = PlanStatus(kind: .subscription, planLabel: "Max 20x", windows: [w],
                            credits: nil, costUSD: nil, provenance: .estimated,
                            generatedAt: exportNow)
    let json = try decode(try UsageExport.encode(status))
    let window = (json["windows"] as! [[String: Any]])[0]
    #expect(window["pace"] == nil)
    #expect(window["resetsAt"] == nil)
}

@Test func encodesAnEmptyStatusWithoutCrashing() throws {
    // Never lie or crash on bad input: an unknown plan still produces valid JSON.
    let json = try decode(try UsageExport.encode(.empty(now: exportNow)))
    #expect((json["windows"] as! [[String: Any]]).isEmpty)
    #expect(json["headlinePercent"] == nil)
}

@Test func keysAreSortedSoOutputIsStable() throws {
    let a = try UsageExport.encode(sampleStatus())
    let b = try UsageExport.encode(sampleStatus())
    #expect(a == b)
}

struct UsageExportWriterTests {

    @Test func writesTheFileAtomically() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("usage.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        try UsageExportWriter(url: url).write(sampleStatus())
        let json = try decode(try Data(contentsOf: url))
        #expect(json["schemaVersion"] as? Int == UsageExport.schemaVersion)
    }

    @Test func createsTheParentDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("nested/usage.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        try UsageExportWriter(url: url).write(sampleStatus())
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func removeDeletesTheFileAndIsSafeWhenAbsent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("usage.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = UsageExportWriter(url: url)
        try writer.write(sampleStatus())
        writer.remove()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        writer.remove()   // must not throw or crash
    }
}
