import SwiftUI
import CCTTCore

/// Cost / tokens per project: a bar chart above a sortable table.
struct ProjectsTab: View {
    let breakdown: Breakdown
    let unit: DisplayUnit

    var body: some View {
        let rows = dimensionRows(breakdown.byProject)
        if rows.isEmpty {
            TabEmptyState(message: "No project activity for the selected time range.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                DimensionBarChart(rows: rows, unit: unit)
                DimensionTable(rows: rows, unit: unit, keyHeader: "Project")
            }
            .padding()
        }
    }
}

#Preview("Projects") {
    ProjectsTab(breakdown: .previewSample, unit: .tokens).frame(width: 620, height: 460)
}

#Preview("Projects · empty") {
    ProjectsTab(breakdown: .empty, unit: .tokens).frame(width: 620, height: 460)
}
