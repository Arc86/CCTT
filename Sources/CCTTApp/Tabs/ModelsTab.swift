import SwiftUI
import Charts
import CCTTCore

/// Per-model token composition (fresh input / cache read / output) as a stacked
/// bar, with a cache-efficiency callout and a sortable table.
struct ModelsTab: View {
    let breakdown: Breakdown
    let unit: DisplayUnit

    /// One stacked segment for the composition chart.
    private struct Segment: Identifiable {
        let id = UUID()
        let model: String
        let category: String
        let tokens: Int
    }

    private var segments: [Segment] {
        breakdown.byModel.flatMap { m -> [Segment] in
            [Segment(model: m.key, category: "Input", tokens: m.totals.input + m.totals.cacheCreation),
             Segment(model: m.key, category: "Cache read", tokens: m.totals.cacheRead),
             Segment(model: m.key, category: "Output", tokens: m.totals.output)]
        }
    }

    var body: some View {
        let rows = dimensionRows(breakdown.byModel)
        if rows.isEmpty {
            TabEmptyState(message: "No model activity for the selected time range.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                cacheCallout
                Chart(segments) { seg in
                    BarMark(x: .value("Tokens", seg.tokens), y: .value("Model", seg.model))
                        .foregroundStyle(by: .value("Kind", seg.category))
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = value.as(Double.self) { Text(DefaultPaths.formatTokens(Int(d))) }
                        }
                    }
                }
                .frame(minHeight: 180)
                DimensionTable(rows: rows, unit: unit, keyHeader: "Model")
            }
            .padding()
        }
    }

    /// cache-read ÷ all input-side tokens — how much context came from cache.
    private var cacheCallout: some View {
        let t = breakdown.totals
        let inputSide = t.input + t.cacheCreation + t.cacheRead
        let pct = inputSide > 0 ? Double(t.cacheRead) / Double(inputSide) : 0
        return Label("Cache efficiency: \(Int((pct * 100).rounded()))% of input served from cache",
                     systemImage: "bolt.horizontal.circle")
            .font(.callout).foregroundStyle(.secondary)
    }
}

#Preview("Models") {
    ModelsTab(breakdown: .previewSample, unit: .tokens).frame(width: 620, height: 460)
}
