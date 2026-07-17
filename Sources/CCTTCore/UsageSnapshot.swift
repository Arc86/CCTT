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
    // Rolling / calendar windows for the limit engine (Plan 2).
    public let fiveHour: TokenTotals      // the currently-open 5h block (zero when none)
    /// The currently-open anchored 5-hour block, or `nil` when none is open.
    /// Carries `start`/`end` so `LimitEngine` can derive a local `resetsAt`.
    public let fiveHourBlock: SessionBlock?
    public let weekly: TokenTotals        // rolling last 7 days
    public let monthToDate: TokenTotals   // calendar month-to-date (UTC)
    public let monthByModel: [Rollup]     // month-to-date, per model (for $ cost)
    public let parseErrors: Int
    public let generatedAt: Date

    public static func empty(now: Date) -> UsageSnapshot {
        UsageSnapshot(overall: .zero, byProject: [], byModel: [], bySession: [],
                      byAgentKind: [], bySkill: [], byPlugin: [],
                      fiveHour: .zero, weekly: .zero, monthToDate: .zero, monthByModel: [],
                      parseErrors: 0, generatedAt: now)
    }

    public init(overall: TokenTotals, byProject: [Rollup], byModel: [Rollup],
                bySession: [Rollup], byAgentKind: [Rollup], bySkill: [Rollup],
                byPlugin: [Rollup], fiveHour: TokenTotals,
                fiveHourBlock: SessionBlock? = nil, weekly: TokenTotals,
                monthToDate: TokenTotals, monthByModel: [Rollup],
                parseErrors: Int, generatedAt: Date) {
        self.overall = overall; self.byProject = byProject; self.byModel = byModel
        self.bySession = bySession; self.byAgentKind = byAgentKind
        self.bySkill = bySkill; self.byPlugin = byPlugin
        self.fiveHour = fiveHour; self.fiveHourBlock = fiveHourBlock
        self.weekly = weekly
        self.monthToDate = monthToDate; self.monthByModel = monthByModel
        self.parseErrors = parseErrors; self.generatedAt = generatedAt
    }
}
