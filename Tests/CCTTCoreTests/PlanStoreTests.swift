import Testing
import Foundation
@testable import CCTTCore

private let now = Date(timeIntervalSince1970: 1_783_000_000)

private func writeConfig(_ json: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cctt-store-\(UUID().uuidString).json")
    try! Data(json.utf8).write(to: url)
    return url
}

@MainActor
@Test func refreshDetectsPlanAndComputesEstimate() async {
    let url = writeConfig(#"{"oauthAccount":{"organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x"}}"#)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PlanStore(configURL: url, environment: [:],
                          provider: UnavailableLiveLimitProvider(),
                          clock: { now })
    let snap = aggregate(
        events: [UsageEvent.fixture(timestamp: now.addingTimeInterval(-600),
                                    input: 1_000_000, output: 0,
                                    requestId: "r1", messageId: "m1")],
        parseErrors: 0, now: now)
    await store.refresh(snapshot: snap)
    #expect(store.plan.kind == .subscription)
    #expect(store.status.provenance == .estimated)
    #expect(abs(store.status.headlinePercent! - 0.2) < 1e-9)   // 1M / 5M cap
}

@MainActor
@Test func planStoreStartsEmpty() {
    let store = PlanStore(configURL: URL(fileURLWithPath: "/definitely/missing.json"),
                          clock: { Date(timeIntervalSince1970: 0) })
    #expect(store.status.headlinePercent == nil)
    #expect(store.plan.kind == .unknown)
}

@MainActor
@Test func refreshUsesLiveProviderWhenAvailable() async {
    let url = writeConfig(#"{"oauthAccount":{"organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x"}}"#)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PlanStore(configURL: url, environment: [:],
                          provider: StaticLiveLimitProvider(LiveLimits(fiveHourPercent: 0.9)),
                          clock: { now })
    await store.refresh(snapshot: aggregate(events: [], parseErrors: 0, now: now))
    #expect(store.status.provenance == .live)
    #expect(store.status.headlinePercent == 0.9)
}
