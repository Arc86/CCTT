import Foundation
import CCTTCore

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
