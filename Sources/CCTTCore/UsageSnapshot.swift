import Foundation

/// One grouped bucket (e.g. a single project or model) and its summed tokens.
public struct Rollup: Sendable, Equatable {
    public let key: String
    public let totals: TokenTotals
    public init(key: String, totals: TokenTotals) {
        self.key = key; self.totals = totals
    }
}

/// Immutable aggregated view of all usage, published to the UI.
public struct UsageSnapshot: Sendable, Equatable {
    public let overall: TokenTotals
    public let byProject: [Rollup]
    public let byModel: [Rollup]
    public let bySession: [Rollup]
    public let byAgentKind: [Rollup]
    public let bySkill: [Rollup]
    public let byPlugin: [Rollup]
    public let parseErrors: Int
    public let generatedAt: Date

    public static func empty(now: Date) -> UsageSnapshot {
        UsageSnapshot(overall: .zero, byProject: [], byModel: [], bySession: [],
                      byAgentKind: [], bySkill: [], byPlugin: [],
                      parseErrors: 0, generatedAt: now)
    }

    public init(overall: TokenTotals, byProject: [Rollup], byModel: [Rollup],
                bySession: [Rollup], byAgentKind: [Rollup], bySkill: [Rollup],
                byPlugin: [Rollup], parseErrors: Int, generatedAt: Date) {
        self.overall = overall; self.byProject = byProject; self.byModel = byModel
        self.bySession = bySession; self.byAgentKind = byAgentKind
        self.bySkill = bySkill; self.byPlugin = byPlugin
        self.parseErrors = parseErrors; self.generatedAt = generatedAt
    }
}
