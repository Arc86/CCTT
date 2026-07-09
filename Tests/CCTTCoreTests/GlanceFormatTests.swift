import Testing
import Foundation
@testable import CCTTCore

private func status(percent: Double?, provenance: Provenance) -> PlanStatus {
    PlanStatus(kind: .subscription, planLabel: "Max 5x",
        windows: [WindowStatus(kind: .fiveHour, usedTokens: 0, capTokens: 100,
                               percent: percent, resetsAt: nil, provenance: provenance)],
        credits: nil, costUSD: nil, provenance: provenance, generatedAt: Date())
}

@Test func configURLIsUnderHome() {
    #expect(DefaultPaths.configURL.path.hasSuffix(".claude.json"))
}

@Test func formatsEstimatedPercentWithTilde() {
    #expect(DefaultPaths.formatPercent(status(percent: 0.68, provenance: .estimated),
                                       fallbackTokens: 999) == "~68%")
}

@Test func formatsLivePercentWithoutTilde() {
    #expect(DefaultPaths.formatPercent(status(percent: 0.5, provenance: .live),
                                       fallbackTokens: 0) == "50%")
}

@Test func fallsBackToTokensWhenNoHeadline() {
    #expect(DefaultPaths.formatPercent(.empty(now: Date()),
                                       fallbackTokens: 12_345) == "12.3K")
}
