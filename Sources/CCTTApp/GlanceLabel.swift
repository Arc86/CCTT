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
                        if let reset = w.resetsAt {
                            Text(resetText(reset)).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(percentText(w.percent))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.callout)
                }
            }

            creditsLine

            topOffenders

            if snapshot.parseErrors > 0 {
                Text("\(snapshot.parseErrors) unparsed lines")
                    .font(.caption2).foregroundStyle(.orange)
            }

            Divider()
            HStack {
                Button("Open Details…") { openWindow(id: "details") }
                Spacer()
                SettingsLink { Image(systemName: "gear") }
                    .buttonStyle(.borderless)
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    /// Credit balance / spend, only when extra usage is enabled. Live values are
    /// real billed money (`.billed`); the grant-cache fallback is `.estimated`.
    @ViewBuilder
    private var creditsLine: some View {
        if let credits = status.credits, credits.enabled {
            Divider()
            HStack {
                Text("Credits").font(.caption.bold())
                Spacer()
                Text(creditsText(credits))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func creditsText(_ c: CreditsStatus) -> String {
        let left = MoneyFormat.string(minorUnits: c.balanceMinorUnits, currency: c.currency)
        guard let used = c.usedThisPeriodMinorUnits else { return "\(left) left" }
        return "\(left) left · \(MoneyFormat.string(minorUnits: used, currency: c.currency)) used"
    }

    private func resetText(_ date: Date) -> String {
        "resets \(date.formatted(.relative(presentation: .named)))"
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
