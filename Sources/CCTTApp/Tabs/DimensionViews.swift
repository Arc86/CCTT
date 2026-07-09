import SwiftUI
import Charts
import CCTTCore

/// One table/chart row for a single dimension bucket, with its share of the total.
struct DimensionRow: Identifiable {
    var id: String { key }
    let key: String
    let totals: TokenTotals
    let costUSD: Double
    let percent: Double   // 0...1 share of the grand total (by tokens)

    /// The value to plot/sort by in the currently selected unit.
    func value(_ unit: DisplayUnit) -> Double {
        unit == .dollars ? costUSD : Double(totals.total)
    }
}

/// Turn costed rollups into rows carrying each bucket's % of the token total.
func dimensionRows(_ rollups: [CostedRollup]) -> [DimensionRow] {
    let grand = rollups.reduce(0) { $0 + $1.totals.total }
    return rollups.map {
        DimensionRow(key: $0.key, totals: $0.totals, costUSD: $0.costUSD,
                     percent: grand > 0 ? Double($0.totals.total) / Double(grand) : 0)
    }
}

/// Horizontal bar chart of the top rows, plotting the selected unit. Empty-safe.
struct DimensionBarChart: View {
    let rows: [DimensionRow]
    let unit: DisplayUnit
    var limit = 12

    var body: some View {
        let top = Array(rows.prefix(limit))
        Chart(top) { row in
            BarMark(
                x: .value("Value", row.value(unit)),
                y: .value("Name", row.key)
            )
            .foregroundStyle(by: .value("Name", row.key))
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Double.self) { Text(axisLabel(d)) }
                }
            }
        }
        .frame(minHeight: 180)
    }

    private func axisLabel(_ d: Double) -> String {
        unit == .dollars ? DefaultPaths.formatUSD(d) : DefaultPaths.formatTokens(Int(d))
    }
}

/// Sortable table: name, tokens (or ≈$), and share of total.
struct DimensionTable: View {
    let rows: [DimensionRow]
    let unit: DisplayUnit
    var keyHeader = "Name"
    @State private var sortOrder = [KeyPathComparator(\DimensionRow.totals.total, order: .reverse)]

    var body: some View {
        Table(sortedRows, sortOrder: $sortOrder) {
            TableColumn(keyHeader, value: \.key) { row in
                Text(row.key).lineLimit(1).truncationMode(.middle)
            }
            TableColumn(unit == .dollars ? "≈ Cost" : "Tokens",
                        value: \.totals.total) { row in
                Text(DefaultPaths.formatValue(totals: row.totals, costUSD: row.costUSD, unit: unit))
                    .monospacedDigit()
            }
            TableColumn("Share", value: \.percent) { row in
                Text("\(Int((row.percent * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .tableColumnHeaders(.visible)
    }

    // Table's sortOrder binding drives interactive header-click sorting.
    private var sortedRows: [DimensionRow] { rows.sorted(using: sortOrder) }
}

/// Friendly, non-alarming empty state for a tab with no data in range.
struct TabEmptyState: View {
    let message: String
    var body: some View {
        ContentUnavailableView("No usage in range", systemImage: "chart.bar",
                               description: Text(message))
    }
}
