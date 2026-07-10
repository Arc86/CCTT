import SwiftUI
import CCTTCore

/// One ranked row for a single dimension bucket, with its share of the total.
struct DimensionRow: Identifiable {
    var id: String { key }
    let key: String
    let totals: TokenTotals
    let costUSD: Double
    let unpricedTokens: Int   // tokens with no known price (→ "n/a", never "$0")
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
                     unpricedTokens: $0.unpricedTokens,
                     percent: grand > 0 ? Double($0.totals.total) / Double(grand) : 0)
    }
}

/// Friendly, non-alarming empty state for a tab with no data in range.
struct TabEmptyState: View {
    let message: String
    var body: some View {
        ContentUnavailableView("No usage in range", systemImage: "chart.bar",
                               description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
