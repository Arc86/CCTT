import SwiftUI
import Charts
import CCTTCore

/// Per-session context size vs. the model ceiling, with auto-compaction points
/// annotated, plus a summary table. Context size is measured tokens, so the
/// $⇄tokens toggle does not apply here.
struct ContextWindowsTab: View {
    let summaries: [ContextSessionSummary]
    let seriesProvider: (String) -> [ContextPoint]
    @State private var selected: String?

    var body: some View {
        if summaries.isEmpty {
            TabEmptyState(message: "No context data for the selected time range.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Session", selection: $selected) {
                    ForEach(summaries, id: \.sessionId) { s in
                        Text(s.sessionId).tag(Optional(s.sessionId))
                    }
                }
                .frame(maxWidth: 320)

                chart

                Table(summaries) {
                    TableColumn("Session") { Text($0.sessionId).lineLimit(1).truncationMode(.middle) }
                    TableColumn("Peak") { Text(DefaultPaths.formatTokens($0.peakContext)).monospacedDigit() }
                    TableColumn("Avg") { Text(DefaultPaths.formatTokens(Int($0.avgContext))).monospacedDigit() }
                    TableColumn("% ceiling") { s in
                        Text("\(Int((s.peakPercentOfCeiling * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(s.peakPercentOfCeiling >= 0.8 ? .orange : .secondary)
                    }
                    TableColumn("Compactions") { Text("\($0.compactionCount)").monospacedDigit() }
                }
            }
            .padding()
            .onAppear { if selected == nil { selected = summaries.first?.sessionId } }
        }
    }

    @ViewBuilder
    private var chart: some View {
        let id = selected ?? summaries.first?.sessionId ?? ""
        let points = seriesProvider(id)
        let ceiling = summaries.first { $0.sessionId == id }?.ceiling ?? 200_000
        Chart {
            ForEach(points, id: \.timestamp) { p in
                LineMark(x: .value("Time", p.timestamp), y: .value("Context", p.contextTokens))
                    .foregroundStyle(.tint)
                if p.isCompaction {
                    PointMark(x: .value("Time", p.timestamp), y: .value("Context", p.contextTokens))
                        .foregroundStyle(.orange)
                        .symbol(.diamond)
                }
            }
            RuleMark(y: .value("Ceiling", ceiling))
                .foregroundStyle(.red.opacity(0.5))
                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Ceiling \(DefaultPaths.formatTokens(ceiling))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Double.self) { Text(DefaultPaths.formatTokens(Int(d))) }
                }
            }
        }
        .frame(minHeight: 200)
    }
}

#Preview("Context Windows") {
    ContextWindowsTab(summaries: ContextSessionSummary.previewRows,
                      seriesProvider: { _ in ContextPoint.previewSeries })
        .frame(width: 640, height: 500)
}
