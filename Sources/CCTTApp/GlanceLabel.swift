import SwiftUI
import CCTTCore

/// Popover contents: plan headline + limit windows + top offenders + actions.
/// Reads the shared stores from the environment; the detail charts live in the
/// separate `DetailView` window opened via "Open Details…".
struct PopoverView: View {
    @Environment(UsageStore.self) private var store
    @Environment(PlanStore.self) private var planStore
    @Environment(DisplayState.self) private var display
    @Environment(\.openWindow) private var openWindow

    private var status: PlanStatus { planStore.status }
    private var snapshot: UsageSnapshot { store.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status.planLabel).font(.headline)
                Spacer()
                Text(provenanceLabel)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if status.windows.isEmpty {
                Text("Total tokens: \(DefaultPaths.formatTokens(snapshot.overall.total))")
                    .font(.subheadline)
            } else {
                ForEach(status.windows, id: \.kind) { w in
                    HStack {
                        Text(windowName(w.kind))
                        Spacer()
                        Text(percentText(w.percent))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.callout)
                }
            }

            if let credits = status.credits, credits.enabled {
                Divider()
                Text("Credits enabled").font(.caption).foregroundStyle(.secondary)
            }

            topOffenders

            if snapshot.parseErrors > 0 {
                Text("\(snapshot.parseErrors) unparsed lines")
                    .font(.caption2).foregroundStyle(.orange)
            }

            Divider()
            HStack {
                Button("Open Details…") { openWindow(id: "details") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    /// Top projects for the selected range, honoring the $⇄tokens unit toggle.
    @ViewBuilder
    private var topOffenders: some View {
        let rows = store.breakdown(range: display.timeRange).byProject.prefix(5)
        if !rows.isEmpty {
            Divider()
            HStack {
                Text("Top projects").font(.caption.bold())
                Spacer()
                Text(display.timeRange.displayName).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(Array(rows), id: \.key) { r in
                HStack {
                    Text(r.key).lineLimit(1)
                    Spacer()
                    Text(DefaultPaths.formatValue(totals: r.totals, costUSD: r.costUSD,
                                                  unit: display.unit))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.callout)
            }
        }
    }

    private var provenanceLabel: String {
        switch status.provenance {
        case .live:      return "Live"
        case .estimated: return "Estimated"
        case .derived:   return "≈ cost"
        case .billed:    return "Billed"
        case .measured:  return "Measured"
        }
    }

    private func windowName(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: return "5-hour"
        case .weekly:   return "Weekly"
        case .month:    return "This month"
        }
    }

    private func percentText(_ p: Double?) -> String {
        guard let p else { return "—" }
        return "\(Int((max(0, p) * 100).rounded()))%"
    }
}
