import Foundation
import CCTTCore

private let previewNow = Date(timeIntervalSince1970: 1_783_000_000)

extension TimeBucket {
    static let previewSeries: [TimeBucket] = (0..<20).map { i in
        let out = [0, 0, 40_000, 120_000, 60_000, 0, 30_000, 90_000, 200_000, 150_000,
                   0, 0, 50_000, 80_000, 0, 20_000, 110_000, 60_000, 0, 30_000][i]
        return TimeBucket(start: previewNow.addingTimeInterval(Double(i - 20) * 900),
                          totals: TokenTotals(output: out, eventCount: out > 0 ? 1 : 0),
                          costUSD: Double(out) / 1_000_000 * 25)
    }
}

extension SessionSummary {
    static let previewRows: [SessionSummary] = [
        SessionSummary(sessionId: "sess-abc123", project: "CCTT",
                       totals: TokenTotals(input: 500_000, output: 80_000, eventCount: 30),
                       costUSD: 4.5, firstActivity: previewNow.addingTimeInterval(-7200),
                       lastActivity: previewNow.addingTimeInterval(-120)),
        SessionSummary(sessionId: "sess-def456", project: "iCSDM",
                       totals: TokenTotals(input: 200_000, output: 30_000, eventCount: 12),
                       costUSD: 1.8, firstActivity: previewNow.addingTimeInterval(-20_000),
                       lastActivity: previewNow.addingTimeInterval(-9000)),
    ]
}

extension ContextSessionSummary {
    static let previewRows: [ContextSessionSummary] = [
        ContextSessionSummary(sessionId: "sess-abc123", model: "claude-opus-4-8[1m]",
                              ceiling: 1_000_000, peakContext: 820_000, avgContext: 410_000,
                              peakPercentOfCeiling: 0.82, compactionCount: 2),
        ContextSessionSummary(sessionId: "sess-def456", model: "claude-opus-4-8",
                              ceiling: 200_000, peakContext: 150_000, avgContext: 90_000,
                              peakPercentOfCeiling: 0.75, compactionCount: 1),
    ]
}

extension ContextPoint {
    static let previewSeries: [ContextPoint] = {
        let sizes = [40_000, 90_000, 150_000, 30_000, 80_000, 140_000, 180_000, 50_000]
        var prev = 0
        return sizes.enumerated().map { i, s in
            let comp = prev >= 10_000 && Double(s) <= 0.5 * Double(prev)
            prev = s
            return ContextPoint(timestamp: previewNow.addingTimeInterval(Double(i - 8) * 600),
                                contextTokens: s, isCompaction: comp)
        }
    }()
}

// Sample data for SwiftUI previews only (not used at runtime).
extension Breakdown {
    static let previewSample: Breakdown = {
        func cr(_ k: String, input: Int = 0, output: Int = 0, cacheCreation: Int = 0,
                cacheRead: Int = 0, cost: Double) -> CostedRollup {
            CostedRollup(key: k,
                         totals: TokenTotals(input: input, output: output,
                                             cacheCreation: cacheCreation, cacheRead: cacheRead,
                                             eventCount: 1),
                         costUSD: cost)
        }
        return Breakdown(
            byProject: [cr("CCTT", input: 800_000, output: 120_000, cost: 6.2),
                        cr("iCSDM", input: 300_000, output: 60_000, cost: 2.1),
                        cr("VoiceRecorder", input: 90_000, output: 20_000, cost: 0.7)],
            byModel: [cr("claude-opus-4-8", input: 900_000, output: 150_000,
                         cacheCreation: 200_000, cacheRead: 1_400_000, cost: 8.4),
                      cr("claude-haiku-4-5", input: 200_000, output: 40_000,
                         cacheRead: 300_000, cost: 0.6)],
            byAgentKind: [cr("main", input: 700_000, output: 120_000, cost: 6.0),
                          cr("subagent", input: 400_000, output: 70_000, cost: 3.0)],
            bySkill: [cr("brainstorming", input: 120_000, output: 20_000, cost: 0.9),
                      cr("executing-plans", input: 80_000, output: 12_000, cost: 0.6)],
            byPlugin: [cr("superpowers", input: 210_000, output: 34_000, cost: 1.6)],
            bySession: [cr("sess-abc", input: 500_000, output: 80_000, cost: 4.0),
                        cr("sess-def", input: 300_000, output: 50_000, cost: 2.4)],
            totals: TokenTotals(input: 1_100_000, output: 190_000,
                                cacheCreation: 200_000, cacheRead: 1_700_000, eventCount: 42),
            totalCostUSD: 9.0)
    }()
}
