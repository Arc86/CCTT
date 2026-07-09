import SwiftUI
import CCTTCore

/// Main-vs-subagent split plus skill and plugin attribution rankings.
struct AgentsSkillsPluginsTab: View {
    let breakdown: Breakdown
    let unit: DisplayUnit

    var body: some View {
        let agent = dimensionRows(breakdown.byAgentKind)
        let skills = dimensionRows(breakdown.bySkill)
        let plugins = dimensionRows(breakdown.byPlugin)

        if agent.isEmpty && skills.isEmpty && plugins.isEmpty {
            TabEmptyState(message: "No agent, skill, or plugin activity for the selected range.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Main vs. subagent", rows: agent, header: "Kind", chart: true)
                    if !skills.isEmpty { section("Skills", rows: skills, header: "Skill") }
                    if !plugins.isEmpty { section("Plugins", rows: plugins, header: "Plugin") }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, rows: [DimensionRow], header: String,
                         chart: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if chart, !rows.isEmpty { DimensionBarChart(rows: rows, unit: unit, limit: 6) }
            DimensionTable(rows: rows, unit: unit, keyHeader: header)
                .frame(minHeight: 120)
        }
    }
}

#Preview("Agents/Skills/Plugins") {
    AgentsSkillsPluginsTab(breakdown: .previewSample, unit: .tokens).frame(width: 620, height: 560)
}
