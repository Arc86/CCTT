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

@Test func encodesCreditsAndSpendLimitWithAllFields() throws {
    let credits = CreditsStatus(enabled: true, balanceMinorUnits: 4_200,
                                usedThisPeriodMinorUnits: 800, currency: "USD",
                                provenance: .billed)
    let spendLimit = SpendLimitStatus(spentMinorUnits: 15_000, capMinorUnits: 50_000,
                                      percent: 0.3, resetsAt: exportNow.addingTimeInterval(86_400),
                                      currency: "EUR", provenance: .derived)
    let w = WindowStatus(kind: .weekly, usedTokens: 1, capTokens: 2, percent: 0.5,
                         resetsAt: nil, provenance: .estimated, pace: nil)
    let status = PlanStatus(kind: .enterprise, planLabel: "Enterprise", windows: [w],
                            credits: credits, spendLimit: spendLimit, costUSD: nil,
                            provenance: .estimated, generatedAt: exportNow)

    let json = try decode(try UsageExport.encode(status))

    let c = json["credits"] as! [String: Any]
    #expect(c["balanceMinorUnits"] as? Int == 4_200)
    #expect(c["usedThisPeriodMinorUnits"] as? Int == 800)
    #expect(c["currency"] as? String == "USD")
    #expect(c["provenance"] as? String == "billed")

    let s = json["spendLimit"] as! [String: Any]
    #expect(s["spentMinorUnits"] as? Int == 15_000)
    #expect(s["capMinorUnits"] as? Int == 50_000)
    #expect(s["percent"] as? Double == 0.3)
    #expect(s["resetsAt"] as? String == "2026-07-18T09:00:00Z")
    #expect(s["currency"] as? String == "EUR")
    #expect(s["provenance"] as? String == "derived")
}

@Test func omitsCreditsAndSpendLimitWhenAbsent() throws {
    let json = try decode(try UsageExport.encode(sampleStatus()))
    #expect(json["credits"] == nil)
    #expect(json["spendLimit"] == nil)
}

@Test func encodesAnEmptyStatusWithoutCrashing() throws {
    // Never lie or crash on bad input: an unknown plan still produces valid JSON.
    let json = try decode(try UsageExport.encode(.empty(now: exportNow)))
    #expect((json["windows"] as! [[String: Any]]).isEmpty)
    #expect(json["headlinePercent"] == nil)
}

// MARK: - Finding 2: the health/staleness channel must reach the export

@Test func encodesLiveAsOfAndLiveHealth() throws {
    // sampleStatus() carries liveAsOf: exportNow, liveHealth: .ok.
    let json = try decode(try UsageExport.encode(sampleStatus()))
    #expect(json["liveAsOf"] as? String == "2026-07-17T09:00:00Z")
    #expect(json["liveHealth"] as? String == "ok")
}

@Test func encodesRateLimitedHealthAsAFlatString() throws {
    // `until` is deliberately dropped — the envelope stays flat and simple, and
    // `until` isn't actionable for a statusline consumer.
    let w = WindowStatus(kind: .weekly, usedTokens: 1, capTokens: 2, percent: 0.5,
                         resetsAt: nil, provenance: .live, pace: nil)
    let status = PlanStatus(kind: .subscription, planLabel: "Max 20x", windows: [w],
                            credits: nil, costUSD: nil, provenance: .live,
                            liveAsOf: exportNow,
                            liveHealth: .rateLimited(until: exportNow.addingTimeInterval(600)),
                            generatedAt: exportNow)
    let json = try decode(try UsageExport.encode(status))
    #expect(json["liveHealth"] as? String == "rateLimited")
}

@Test func encodesNeedsReauthAndDegradedHealth() throws {
    let w = WindowStatus(kind: .weekly, usedTokens: 1, capTokens: 2, percent: 0.5,
                         resetsAt: nil, provenance: .estimated, pace: nil)
    func status(_ health: LiveHealth) -> PlanStatus {
        PlanStatus(kind: .subscription, planLabel: "Max 20x", windows: [w],
                  credits: nil, costUSD: nil, provenance: .estimated,
                  liveAsOf: exportNow, liveHealth: health, generatedAt: exportNow)
    }
    let reauth = try decode(try UsageExport.encode(status(.needsReauth)))
    #expect(reauth["liveHealth"] as? String == "needsReauth")
    let degraded = try decode(try UsageExport.encode(status(.degraded)))
    #expect(degraded["liveHealth"] as? String == "degraded")
}

@Test func omitsLiveAsOfAndLiveHealthWhenNil() throws {
    // No `null` values — the keys must be absent entirely, matching how
    // pace/credits/spendLimit already vanish rather than emitting null.
    let json = try decode(try UsageExport.encode(.empty(now: exportNow)))
    #expect(json["liveAsOf"] == nil)
    #expect(json["liveHealth"] == nil)
    #expect(json.keys.contains("liveAsOf") == false)
    #expect(json.keys.contains("liveHealth") == false)
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
