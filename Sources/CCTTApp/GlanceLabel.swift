import SwiftUI
import CCTTCore

/// Popover contents: plan headline + limit windows + usage breakdown.
/// Richer charts land in Plan 3; this proves the pipeline end-to-end.
struct PopoverView: View {
    let snapshot: UsageSnapshot
    let status: PlanStatus

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

            if !snapshot.byProject.isEmpty {
                Divider()
                Text("Top projects").font(.caption.bold())
                ForEach(snapshot.byProject.prefix(5), id: \.key) { r in
                    HStack {
                        Text(r.key).lineLimit(1)
                        Spacer()
                        Text(DefaultPaths.formatTokens(r.totals.total))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            if snapshot.parseErrors > 0 {
                Text("\(snapshot.parseErrors) unparsed lines")
                    .font(.caption2).foregroundStyle(.orange)
            }
            Divider()
            Button("Quit CCTT") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
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
