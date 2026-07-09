import Testing
import Foundation
@testable import CCTTCore

@Test func headlineIsMostConstrainingWindow() {
    let s = PlanStatus(
        kind: .subscription, planLabel: "Max 5x",
        windows: [
            WindowStatus(kind: .fiveHour, usedTokens: 0, capTokens: 1, percent: 0.2,
                         resetsAt: nil, provenance: .estimated),
            WindowStatus(kind: .weekly, usedTokens: 0, capTokens: 1, percent: 0.5,
                         resetsAt: nil, provenance: .estimated),
        ],
        credits: nil, costUSD: nil, provenance: .estimated, generatedAt: Date())
    #expect(s.headlinePercent == 0.5)
}

@Test func headlineNilWhenNoPercentedWindows() {
    #expect(PlanStatus.empty(now: Date()).headlinePercent == nil)
    let s = PlanStatus(kind: .enterprise, planLabel: "Enterprise",
        windows: [WindowStatus(kind: .weekly, usedTokens: 5, capTokens: nil, percent: nil,
                               resetsAt: nil, provenance: .estimated)],
        credits: nil, costUSD: nil, provenance: .estimated, generatedAt: Date())
    #expect(s.headlinePercent == nil)
}

@Test func emptyIsUnknownWithNoWindows() {
    let s = PlanStatus.empty(now: Date(timeIntervalSince1970: 0))
    #expect(s.kind == .unknown)
    #expect(s.windows.isEmpty)
}
