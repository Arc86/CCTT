import SwiftUI
import Charts
import CCTTCore

/// Spend-over-time chart plus a ranked recent-session table.
struct SessionsTimelineTab: View {
    let timeline: [TimeBucket]
    let sessions: [SessionSummary]
    let unit: DisplayUnit

    var body: some View {
        if timeline.allSatisfy({ $0.totals.total == 0 }) && sessions.isEmpty {
            TabEmptyState(message: "No session activity for the selected time range.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Spend over time").font(.headline)
                Chart(timeline, id: \.start) { bucket in
                    AreaMark(x: .value("Time", bucket.start),
                             y: .value(unit == .dollars ? "Cost" : "Tokens", plotValue(bucket)))
                    .foregroundStyle(.tint.opacity(0.6))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = value.as(Double.self) { Text(axisLabel(d)) }
                        }
                    }
                }
                .frame(minHeight: 160)

                Text("Recent sessions").font(.headline)
                Table(sessions) {
                    TableColumn("Session") { Text($0.sessionId).lineLimit(1).truncationMode(.middle) }
                    TableColumn("Project") { Text($0.project).lineLimit(1) }
                    TableColumn(unit == .dollars ? "≈ Cost" : "Tokens") { s in
                        Text(DefaultPaths.formatValue(totals: s.totals, costUSD: s.costUSD, unit: unit))
                            .monospacedDigit()
                    }
                    TableColumn("Last active") { s in
                        Text(s.lastActivity, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }

    private func plotValue(_ b: TimeBucket) -> Double {
        unit == .dollars ? b.costUSD : Double(b.totals.total)
    }

    private func axisLabel(_ d: Double) -> String {
        unit == .dollars ? DefaultPaths.formatUSD(d) : DefaultPaths.formatTokens(Int(d))
    }
}

#Preview("Sessions & Timeline") {
    SessionsTimelineTab(timeline: TimeBucket.previewSeries,
                        sessions: SessionSummary.previewRows, unit: .tokens)
        .frame(width: 640, height: 480)
}
