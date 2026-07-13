import SwiftUI
import Charts
import CCTTCore

// MARK: - Shared helpers

/// A session's display label: Claude Code's generated title when known, else a short
/// prefix of the raw session ID (never blank; the full ID goes in a `.help` tooltip).
func sessionLabel(title: String?, sessionId: String) -> String {
    if let title, !title.isEmpty { return title }
    return String(sessionId.prefix(8))
}

/// Compact session duration: "0m", "12m", "1h 3m", "2h".
func formatDuration(_ seconds: TimeInterval) -> String {
    let mins = max(0, Int(seconds / 60))
    if mins < 60 { return "\(mins)m" }
    let h = mins / 60, m = mins % 60
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}

/// The long, sentence-case phrase for a range, used in the hero subheading.
func longRangeName(_ range: TimeRange) -> String {
    switch range {
    case .fiveHour:   return "Last 5 hours"
    case .thisWeek:   return "This week"
    case .last7Days:  return "Last 7 days"
    case .last30Days: return "Last 30 days"
    case .all:        return "All time"
    }
}

private func unitWord(_ unit: DisplayUnit) -> String { unit == .dollars ? "cost" : "tokens" }

private func pct(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

// MARK: - Ranked list

/// A vertical stack of ranked "name — bar — value — %" rows over a set of dimension
/// rollups, in the selected unit. Optionally scrolls past a max height.
struct RankedList: View {
    let rows: [DimensionRow]
    let unit: DisplayUnit
    var nameWidth: CGFloat = 150
    var monospaced = false
    var showPercent = true
    var color: (Int, DimensionRow) -> Color = { i, _ in Dash.paletteColor(i) }
    var barHeight: CGFloat = 9
    var maxHeight: CGFloat? = nil

    var body: some View {
        let maxV = max(rows.map { $0.value(unit) }.max() ?? 1, 1)
        let list = VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                RankedBarRow(
                    name: r.key, nameWidth: nameWidth, monospaced: monospaced,
                    fraction: r.value(unit) / maxV, color: color(i, r),
                    value: DefaultPaths.formatValue(totals: r.totals, costUSD: r.costUSD,
                                                    unit: unit, unpricedTokens: r.unpricedTokens),
                    percent: showPercent ? pct(r.percent) : nil,
                    barHeight: barHeight)
            }
        }
        if let maxHeight {
            ScrollView { list.padding(.trailing, 2) }.frame(maxHeight: maxHeight)
        } else {
            list
        }
    }
}

// MARK: - Hero

/// The shared header for every breakdown tab: the range total, a trend pill, a
/// sparkline of spend over time, and the sessions/turns counts.
struct HeroHeader: View {
    let breakdown: Breakdown
    let delta: Double?
    let sparkValues: [Double]
    let unit: DisplayUnit

    var body: some View {
        HStack(alignment: .bottom, spacing: 30) {
            VStack(alignment: .leading, spacing: 3) {
                Text(unit == .dollars ? "Total cost" : "Total tokens")
                    .font(.system(size: 11)).foregroundStyle(Dash.text2)
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text(DefaultPaths.formatValue(totals: breakdown.totals, costUSD: breakdown.totalCostUSD,
                                                  unit: unit, unpricedTokens: breakdown.unpricedTokens))
                        .font(.system(size: 38, weight: .bold)).monospacedDigit()
                    if let delta { DeltaPill(fraction: delta) }
                }
                Text(unit == .dollars && breakdown.costPartial
                     ? "Some models unpriced — cost is a lower bound."
                     : " ")
                    .font(.system(size: 11)).foregroundStyle(Dash.text3)
            }
            if sparkValues.count > 1 {
                Sparkline(values: sparkValues).padding(.bottom, 4)
            }
            HStack(spacing: 26) {
                stat("Sessions", breakdown.sessionCount)
                stat("Turns", breakdown.turnCount)
            }
            .padding(.bottom, 4)
            Spacer(minLength: 0)
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.formatted()).font(.system(size: 20, weight: .bold)).monospacedDigit()
            Text(label).font(.system(size: 10.5)).foregroundStyle(Dash.text2)
        }
    }
}

// MARK: - Projects

struct ProjectsBody: View {
    let breakdown: Breakdown
    let unit: DisplayUnit

    var body: some View {
        let rows = dimensionRows(breakdown.byProject)
        let branchRows = dimensionRows(breakdown.byBranch)
        if rows.isEmpty {
            TabEmptyState(message: "No project activity for the selected time range.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    DashCard {
                        CardTitleRow(title: "Share of tokens").padding(.bottom, 16)
                        HStack(spacing: 16) {
                            Donut(slices: donutSlices(rows),
                                  centerTitle: DefaultPaths.formatTokens(breakdown.totals.total),
                                  centerSubtitle: "total")
                            VStack(spacing: 9) {
                                ForEach(Array(legend(rows).enumerated()), id: \.offset) { _, l in
                                    LegendItemRow(color: l.color, name: l.name, value: l.pct)
                                }
                            }
                        }
                    }
                    .frame(width: 300)

                    DashCard {
                        CardTitleRow(title: "Ranked by \(unitWord(unit))",
                                     trailing: "\(rows.count) projects").padding(.bottom, 16)
                        RankedList(rows: rows, unit: unit, nameWidth: 120, maxHeight: 190)
                    }
                }
                InsightLine(text: insight(rows))
                if !branchRows.isEmpty {
                    DashCard {
                        CardTitleRow(title: "By git branch",
                                     trailing: "\(branchRows.count) branches").padding(.bottom, 14)
                        RankedList(rows: branchRows, unit: unit, nameWidth: 224, monospaced: true,
                                   showPercent: true, color: { _, _ in Dash.accent },
                                   barHeight: 7, maxHeight: 186)
                    }
                }
            }
        }
    }

    private func donutSlices(_ rows: [DimensionRow]) -> [(Double, Color)] {
        let top = rows.prefix(5)
        var slices = top.enumerated().map { (i, r) in (r.percent, Dash.paletteColor(i)) }
        let others = rows.dropFirst(5).reduce(0) { $0 + $1.percent }
        if others > 0.001 { slices.append((others, Dash.grey)) }
        return slices
    }

    private func legend(_ rows: [DimensionRow]) -> [(color: Color, name: String, pct: String)] {
        var out = rows.prefix(5).enumerated().map {
            (Dash.paletteColor($0.offset), $0.element.key, pct($0.element.percent))
        }
        let others = rows.dropFirst(5).reduce(0) { $0 + $1.percent }
        if others > 0.001 { out.append((Dash.grey, "Others", pct(others))) }
        return out
    }

    private func insight(_ rows: [DimensionRow]) -> String {
        guard let top = rows.first else { return "" }
        let tail = top.percent > 0.5 ? "more than every other project combined."
                                     : "the largest single share."
        return "\(top.key) drove \(pct(top.percent)) of spend — \(tail)"
    }
}

// MARK: - Models

struct ModelsBody: View {
    let breakdown: Breakdown
    let unit: DisplayUnit

    private let legendItems: [(name: String, color: Color)] = [
        ("Input", Color(hex: 0x5AC8FA)), ("Cache read", Dash.accent), ("Output", Color(hex: 0xFF9500)),
    ]

    var body: some View {
        let rows = dimensionRows(breakdown.byModel)
        if rows.isEmpty {
            TabEmptyState(message: "No model activity for the selected time range.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                CalloutBanner(systemImage: "bolt.horizontal.circle",
                              bold: "Cache efficiency \(cacheEfficiency)",
                              rest: "of input-side tokens served from cache — most context isn't re-billed.")
                DashCard {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Token composition by model").font(.system(size: 12.5, weight: .semibold))
                        Spacer(minLength: 8)
                        SwatchLegend(items: legendItems)
                    }
                    .padding(.bottom, 16)
                    let maxTotal = max(breakdown.byModel.map { $0.totals.total }.max() ?? 1, 1)
                    VStack(spacing: 15) {
                        ForEach(breakdown.byModel, id: \.key) { m in
                            CompositionRow(
                                name: m.key,
                                value: DefaultPaths.formatValue(totals: m.totals, costUSD: m.costUSD,
                                                                unit: unit, unpricedTokens: m.unpricedTokens),
                                barFraction: Double(m.totals.total) / Double(maxTotal),
                                segments: composition(m.totals))
                        }
                    }
                }
                DashCard {
                    CardTitleRow(title: "Ranked by \(unitWord(unit))",
                                 trailing: "\(rows.count) models").padding(.bottom, 14)
                    RankedList(rows: rows, unit: unit, nameWidth: 180, monospaced: true)
                }
            }
        }
    }

    private func composition(_ t: TokenTotals) -> [(Double, Color)] {
        let total = max(t.total, 1)
        let inputSide = t.input + t.cacheCreation
        return [(Double(inputSide) / Double(total), Color(hex: 0x5AC8FA)),
                (Double(t.cacheRead) / Double(total), Dash.accent),
                (Double(t.output) / Double(total), Color(hex: 0xFF9500))]
    }

    private var cacheEfficiency: String {
        let t = breakdown.totals
        let inputSide = t.input + t.cacheCreation + t.cacheRead
        return inputSide > 0 ? pct(Double(t.cacheRead) / Double(inputSide)) : "0%"
    }
}

// MARK: - Agents

struct AgentsBody: View {
    let breakdown: Breakdown
    let unit: DisplayUnit

    var body: some View {
        let agent = dimensionRows(breakdown.byAgentKind)
        let skills = dimensionRows(breakdown.bySkill)
        let plugins = dimensionRows(breakdown.byPlugin)

        if agent.isEmpty && skills.isEmpty && plugins.isEmpty {
            TabEmptyState(message: "No agent, skill, or plugin activity for the selected range.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    DashCard {
                        CardTitleRow(title: "Main vs. subagent").padding(.bottom, 16)
                        HStack(spacing: 16) {
                            Donut(slices: agent.map { ($0.percent, agentColor($0)) },
                                  centerTitle: pct(agent.first { $0.key == "main" }?.percent ?? 0),
                                  centerSubtitle: "main")
                            VStack(spacing: 10) {
                                ForEach(agent) { r in
                                    LegendItemRow(color: agentColor(r), name: r.key, value: pct(r.percent))
                                }
                            }
                        }
                    }
                    .frame(width: 300)

                    DashCard {
                        CardTitleRow(title: "Attribution").padding(.bottom, 16)
                        RankedList(rows: agent, unit: unit, nameWidth: 100, showPercent: false,
                                   color: { _, r in agentColor(r) })
                    }
                }
                if !skills.isEmpty || !plugins.isEmpty {
                    HStack(alignment: .top, spacing: 16) {
                        if !skills.isEmpty {
                            DashCard {
                                CardTitleRow(title: "Skills", trailing: "\(skills.count)").padding(.bottom, 14)
                                RankedList(rows: skills, unit: unit, nameWidth: 130, showPercent: false,
                                           barHeight: 7, maxHeight: 210)
                            }
                        }
                        if !plugins.isEmpty {
                            DashCard {
                                CardTitleRow(title: "Plugins", trailing: "\(plugins.count)").padding(.bottom, 14)
                                RankedList(rows: plugins, unit: unit, nameWidth: 120, showPercent: false,
                                           color: { i, _ in Dash.paletteColor(i + 2) },
                                           barHeight: 7, maxHeight: 210)
                            }
                        }
                    }
                }
            }
        }
    }

    private func agentColor(_ r: DimensionRow) -> Color {
        r.key == "subagent" ? Dash.paletteColor(3) : Dash.accent
    }
}

// MARK: - Sessions

struct SessionsBody: View {
    let timeline: [TimeBucket]
    let hourly: [HourBucket]
    let sessions: [SessionSummary]
    let unit: DisplayUnit
    var rangeName: String = ""

    var body: some View {
        if timeline.allSatisfy({ $0.totals.total == 0 }) && sessions.isEmpty {
            TabEmptyState(message: "No session activity for the selected time range.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                spendCard
                if hourly.contains(where: { $0.totals.total > 0 }) { hourCard }
                sessionsCard
            }
        }
    }

    private var spendCard: some View {
        let peak = timeline.map { plot($0) }.max() ?? 0
        return DashCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Spend over time").font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("peak \(axis(peak))").font(.system(size: 10.5)).foregroundStyle(Dash.text3).monospacedDigit()
            }
            .padding(.bottom, 12)
            Chart(timeline, id: \.start) { b in
                AreaMark(x: .value("Time", b.start), y: .value("Spend", plot(b)))
                    .foregroundStyle(Dash.accent.opacity(0.12))
                LineMark(x: .value("Time", b.start), y: .value("Spend", plot(b)))
                    .foregroundStyle(Dash.accent).lineStyle(.init(lineWidth: 2))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 150)
            HStack {
                Text(rangeName).font(.system(size: 10)).foregroundStyle(Dash.text3)
                Spacer()
                Text("now").font(.system(size: 10)).foregroundStyle(Dash.text3)
            }
            .padding(.top, 4)
        }
    }

    private var hourCard: some View {
        let maxAvg = max(hourly.map { $0.averageTokensPerActiveDay }.max() ?? 1, 1)
        return DashCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Usage by hour of day").font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("avg / active day").font(.system(size: 10.5)).foregroundStyle(Dash.text3)
            }
            .padding(.bottom, 14)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(hourly) { b in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(b.inThrottleWindow ? Dash.warn : Dash.accent.opacity(0.55))
                        .frame(height: max(1, 96 * b.averageTokensPerActiveDay / maxAvg))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
            HStack {
                ForEach(["0h", "6h", "12h", "18h", "23h"], id: \.self) { l in
                    Text(l).font(.system(size: 9.5)).foregroundStyle(Dash.text3)
                    if l != "23h" { Spacer() }
                }
            }
            .padding(.top, 5)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Dash.warn).frame(width: 9, height: 9)
                Text("Shaded hours ≈ Anthropic's weekly-limit window (heuristic).")
                    .font(.system(size: 10.5)).foregroundStyle(Dash.text2)
            }
            .padding(.top, 9)
            .accessibilityLabel("Average tokens per active day by hour. Orange bars fall in "
                                + "Anthropic's estimated weekly-limit window.")
        }
    }

    private var sessionsCard: some View {
        DashCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent sessions").font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("\(sessions.count) total").font(.system(size: 11)).foregroundStyle(Dash.text3)
            }
            .padding(.bottom, 8)
            LightTableHeader {
                LightCol("Title", .flexible)
                LightCol("Project", .width(96))
                LightCol(unit == .dollars ? "≈ Cost" : "Tokens", .width(74), .trailing)
                LightCol("Duration", .width(58), .trailing)
                LightCol("Last active", .width(82), .trailing)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sessions) { s in
                        LightRow {
                            LightCell(sessionLabel(title: s.title, sessionId: s.sessionId), .flexible)
                                .help(s.sessionId)
                            LightCell(s.project, .width(96), color: Dash.text2)
                            LightCell(DefaultPaths.formatValue(totals: s.totals, costUSD: s.costUSD, unit: unit),
                                      .width(74), .trailing, weight: .semibold, mono: true)
                            LightCell(formatDuration(s.lastActivity.timeIntervalSince(s.firstActivity)),
                                      .width(58), .trailing, color: Dash.text2, mono: true)
                            LightCell(s.lastActivity.formatted(.relative(presentation: .named)),
                                      .width(82), .trailing, color: Dash.text2)
                        }
                    }
                }
            }
            .frame(maxHeight: 216)
        }
    }

    private func plot(_ b: TimeBucket) -> Double { unit == .dollars ? b.costUSD : Double(b.totals.total) }
    private func axis(_ d: Double) -> String {
        unit == .dollars ? DefaultPaths.formatUSD(d) : DefaultPaths.formatTokens(Int(d))
    }
}

// MARK: - Context

struct ContextBody: View {
    let summaries: [ContextSessionSummary]
    let seriesProvider: (String) -> [ContextPoint]
    @Binding var selected: String?

    var body: some View {
        if summaries.isEmpty {
            TabEmptyState(message: "No context data for the selected time range.")
        } else {
            let id = selected ?? summaries.first?.sessionId ?? ""
            VStack(alignment: .leading, spacing: 14) {
                chips
                chartCard(id: id)
                tableCard
            }
            .onAppear { if selected == nil { selected = summaries.first?.sessionId } }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(summaries, id: \.sessionId) { s in
                    let on = s.sessionId == (selected ?? summaries.first?.sessionId)
                    Button { selected = s.sessionId } label: {
                        Text(sessionLabel(title: s.title, sessionId: s.sessionId))
                            .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(on ? Dash.accent : Dash.text2)
                            .padding(.vertical, 6).padding(.horizontal, 12)
                            .background(on ? Dash.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(on ? .clear : Dash.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 2)
        }
    }

    private func chartCard(id: String) -> some View {
        let points = seriesProvider(id)
        let cur = summaries.first { $0.sessionId == id }
        let ceiling = cur?.ceiling ?? 200_000
        return DashCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Context size over time").font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("peak \(DefaultPaths.formatTokens(cur?.peakContext ?? 0)) · ceiling \(DefaultPaths.formatTokens(ceiling))")
                    .font(.system(size: 10.5)).foregroundStyle(Dash.text3).monospacedDigit()
            }
            .padding(.bottom, 12)
            Chart {
                ForEach(points, id: \.timestamp) { p in
                    AreaMark(x: .value("Time", p.timestamp), y: .value("Context", p.contextTokens))
                        .foregroundStyle(Dash.accent.opacity(0.12))
                    LineMark(x: .value("Time", p.timestamp), y: .value("Context", p.contextTokens))
                        .foregroundStyle(Dash.accent).lineStyle(.init(lineWidth: 2))
                    if p.isCompaction {
                        PointMark(x: .value("Time", p.timestamp), y: .value("Context", p.contextTokens))
                            .foregroundStyle(Dash.warn).symbol(.diamond)
                    }
                }
                RuleMark(y: .value("Ceiling", ceiling))
                    .foregroundStyle(Dash.danger.opacity(0.55))
                    .lineStyle(.init(lineWidth: 1, dash: [5, 4]))
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text(DefaultPaths.formatTokens(Int(d))) } }
            } }
            .frame(height: 190)
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Rectangle().fill(Dash.warn).frame(width: 9, height: 9).rotationEffect(.degrees(45))
                    Text("Auto-compaction").font(.system(size: 10.5)).foregroundStyle(Dash.text2)
                }
                HStack(spacing: 6) {
                    Rectangle().fill(Dash.danger.opacity(0.6)).frame(width: 12, height: 2)
                    Text("Model ceiling").font(.system(size: 10.5)).foregroundStyle(Dash.text2)
                }
            }
            .padding(.top, 8)
        }
    }

    private var tableCard: some View {
        DashCard {
            Text("Sessions").font(.system(size: 12.5, weight: .semibold)).padding(.bottom, 8)
            LightTableHeader {
                LightCol("Session", .flexible)
                LightCol("Peak", .width(74), .trailing)
                LightCol("Avg", .width(74), .trailing)
                LightCol("% ceiling", .width(70), .trailing)
                LightCol("Compactions", .width(82), .trailing)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(summaries, id: \.sessionId) { s in
                        let on = s.sessionId == (selected ?? summaries.first?.sessionId)
                        let near = s.peakPercentOfCeiling >= 0.8
                        Button { selected = s.sessionId } label: {
                            LightRow(background: on ? Dash.accentSoft : .clear) {
                                LightCell(sessionLabel(title: s.title, sessionId: s.sessionId), .flexible)
                                    .help(s.sessionId)
                                LightCell(DefaultPaths.formatTokens(s.peakContext), .width(74), .trailing, mono: true)
                                LightCell(DefaultPaths.formatTokens(Int(s.avgContext)), .width(74), .trailing,
                                          color: Dash.text2, mono: true)
                                LightCell(pct(s.peakPercentOfCeiling), .width(70), .trailing,
                                          color: near ? Dash.warn : Dash.text2, mono: true)
                                LightCell("\(s.compactionCount)", .width(82), .trailing,
                                          color: Dash.text2, mono: true)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 230)
        }
    }
}

// MARK: - Plan

struct PlanBody: View {
    let status: PlanStatus
    let breakdown: Breakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Current plan").font(.system(size: 11)).foregroundStyle(Dash.text2)
                HStack(spacing: 12) {
                    Text(status.planLabel).font(.system(size: 30, weight: .bold))
                    StatusPill(text: statusText, color: statusColor)
                }
                Text(summary).font(.system(size: 11.5)).foregroundStyle(Dash.text3)
            }

            if let spend = status.spendLimit {
                HStack(alignment: .top, spacing: 16) {
                    MeterCard(label: "Spend limit", sub: "Monthly budget",
                              fraction: spend.percent, usedText: spentUsed(spend),
                              resets: spendResets(spend))
                }
                InsightLine(text: "You've spent \(MoneyFormat.string(minorUnits: spend.spentMinorUnits, currency: spend.currency)) of your \(MoneyFormat.string(minorUnits: spend.capMinorUnits, currency: spend.currency)) spend limit.",
                            color: statusColor)
            } else if status.windows.isEmpty {
                InsightLine(text: "No live limits yet — enable them in Settings, or figures fall back to plan estimates.",
                            color: Dash.warn)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(status.windows, id: \.kind) { w in
                        MeterCard(label: label(w.kind), sub: sub(w.kind),
                                  fraction: w.percent, usedText: used(w), resets: resets(w))
                    }
                }
                if let insight { InsightLine(text: insight, color: statusColor) }
            }

            let models = dimensionRows(breakdown.byModel)
            if !models.isEmpty {
                DashCard {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Usage by model").font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Text("share of range total").font(.system(size: 11)).foregroundStyle(Dash.text3)
                    }
                    .padding(.bottom, 14)
                    RankedList(rows: models, unit: .tokens, nameWidth: 180, monospaced: true,
                               color: { _, r in Dash.meterColor(r.percent) })
                    Text("Limits are estimated from local usage and Anthropic's published windows — actual limits may differ.")
                        .font(.system(size: 10.5)).foregroundStyle(Dash.text3)
                        .padding(.top, 8)
                }
            }
        }
    }

    // Status pill from the most-constrained window.
    private var peak: Double? { status.headlinePercent }
    private var statusText: String {
        guard let p = peak else { return "Estimated" }
        return p >= 0.9 ? "Near limit" : p >= 0.7 ? "Approaching limit" : "Healthy"
    }
    private var statusColor: Color {
        guard let p = peak else { return Dash.grey }
        return p >= 0.9 ? Dash.danger : p >= 0.7 ? Dash.warn : Dash.good
    }
    private var summary: String {
        if let s = status.spendLimit {
            guard let r = s.resetsAt else { return "Monthly spend limit" }
            return "Spend limit resets \(r.formatted(.relative(presentation: .named)))"
        }
        let resets = status.windows.compactMap { w -> String? in
            guard let r = w.resetsAt else { return nil }
            return "\(label(w.kind).lowercased()) resets \(r.formatted(.relative(presentation: .named)))"
        }
        return resets.isEmpty ? "Rolling usage windows" : resets.joined(separator: " · ")
    }
    private var insight: String? {
        guard let p = peak,
              let w = status.windows.max(by: { ($0.percent ?? 0) < ($1.percent ?? 0) }) else { return nil }
        return "You've used \(pct(p)) of your \(label(w.kind).lowercased()) limit."
    }

    private func label(_ k: WindowKind) -> String {
        switch k { case .fiveHour: return "Session"; case .weekly: return "Weekly"; case .month: return "This month" }
    }
    private func sub(_ k: WindowKind) -> String {
        switch k { case .fiveHour: return "5-hour window"; case .weekly: return "7-day rolling"; case .month: return "Calendar month" }
    }
    private func used(_ w: WindowStatus) -> String {
        let cap = w.capTokens.map { DefaultPaths.formatTokens($0) } ?? "—"
        return "\(DefaultPaths.formatTokens(w.usedTokens)) / \(cap)"
    }
    private func resets(_ w: WindowStatus) -> String? {
        w.resetsAt.map { "Resets \($0.formatted(.relative(presentation: .named)))" }
    }
    private func spentUsed(_ s: SpendLimitStatus) -> String {
        "\(MoneyFormat.string(minorUnits: s.spentMinorUnits, currency: s.currency)) / \(MoneyFormat.string(minorUnits: s.capMinorUnits, currency: s.currency))"
    }
    private func spendResets(_ s: SpendLimitStatus) -> String? {
        s.resetsAt.map { "Resets \($0.formatted(.relative(presentation: .named)))" }
    }
}

// MARK: - Lightweight table primitives
//
// The design's tables are inline card rows (not a macOS `Table`), so these render
// header + rows with fixed/flex columns to match, while staying accessible.

enum LightWidth { case flexible; case width(CGFloat) }

private extension View {
    @ViewBuilder func lightColumn(_ w: LightWidth, _ trailing: Bool) -> some View {
        switch w {
        case .flexible: frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        case .width(let x): frame(width: x, alignment: trailing ? .trailing : .leading)
        }
    }
}

struct LightCol: View {
    let title: String
    let w: LightWidth
    let trailing: Bool
    init(_ title: String, _ w: LightWidth, _ align: Alignment = .leading) {
        self.title = title; self.w = w; self.trailing = (align == .trailing)
    }
    var body: some View {
        Text(title).font(.system(size: 10)).foregroundStyle(Dash.text2)
            .lineLimit(1).lightColumn(w, trailing)
    }
}

struct LightTableHeader<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.vertical, 6).padding(.horizontal, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(Dash.hairline).frame(height: 1) }
    }
}

struct LightCell: View {
    let text: String
    let w: LightWidth
    let trailing: Bool
    var color: Color = .primary
    var weight: Font.Weight = .regular
    var mono: Bool = false
    init(_ text: String, _ w: LightWidth, _ align: Alignment = .leading,
         color: Color = .primary, weight: Font.Weight = .regular, mono: Bool = false) {
        self.text = text; self.w = w; self.trailing = (align == .trailing)
        self.color = color; self.weight = weight; self.mono = mono
    }
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: weight))
            .modifier(MonoIf(mono))
            .foregroundStyle(color)
            .lineLimit(1).truncationMode(.tail)
            .lightColumn(w, trailing)
    }
}

private struct MonoIf: ViewModifier {
    let on: Bool
    init(_ on: Bool) { self.on = on }
    func body(content: Content) -> some View { on ? AnyView(content.monospacedDigit()) : AnyView(content) }
}

struct LightRow<Content: View>: View {
    var background: Color = .clear
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.vertical, 8).padding(.horizontal, 4)
            .background(background)
            .overlay(alignment: .bottom) { Rectangle().fill(Dash.hairline.opacity(0.6)).frame(height: 1) }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Projects") {
    ScrollView { VStack(spacing: 18) {
        HeroHeader(breakdown: .previewSample, delta: 0.12,
                   sparkValues: TimeBucket.previewSeries.map { Double($0.totals.total) }, unit: .tokens)
        ProjectsBody(breakdown: .previewSample, unit: .tokens)
    }.padding(20) }.frame(width: 820, height: 640)
}

#Preview("Models") {
    ScrollView { ModelsBody(breakdown: .previewSample, unit: .tokens).padding(20) }
        .frame(width: 820, height: 560)
}

#Preview("Agents") {
    ScrollView { AgentsBody(breakdown: .previewSample, unit: .tokens).padding(20) }
        .frame(width: 820, height: 560)
}

#Preview("Sessions") {
    ScrollView { SessionsBody(timeline: TimeBucket.previewSeries, hourly: HourBucket.previewProfile,
                              sessions: SessionSummary.previewRows, unit: .tokens).padding(20) }
        .frame(width: 820, height: 700)
}

#Preview("Context") {
    ScrollView { ContextBody(summaries: ContextSessionSummary.previewRows,
                             seriesProvider: { _ in ContextPoint.previewSeries },
                             selected: .constant(nil)).padding(20) }
        .frame(width: 820, height: 640)
}

#Preview("Plan") {
    let status = PlanStatus(
        kind: .subscription, planLabel: "Claude Max 20×",
        windows: [
            WindowStatus(kind: .fiveHour, usedTokens: 12_400_000, capTokens: 26_500_000, percent: 0.47,
                         resetsAt: Date(timeIntervalSinceNow: 8000), provenance: .live),
            WindowStatus(kind: .weekly, usedTokens: 452_000_000, capTokens: 665_000_000, percent: 0.81,
                         resetsAt: Date(timeIntervalSinceNow: 300_000), provenance: .live),
        ],
        credits: nil, costUSD: nil, provenance: .live, generatedAt: Date())
    return ScrollView { PlanBody(status: status, breakdown: .previewSample).padding(20) }
        .frame(width: 820, height: 560)
}
