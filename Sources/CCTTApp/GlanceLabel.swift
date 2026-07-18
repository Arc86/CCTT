import SwiftUI
import AppKit
import CCTTCore

/// Popover contents: plan headline + limit gauges + top offenders + actions.
/// Reads the shared stores from the environment; the detail charts live in the
/// separate `DetailView` window opened via "Details…".
struct PopoverView: View {
    @Environment(UsageStore.self) private var store
    @Environment(PlanStore.self) private var planStore
    @Environment(DisplayState.self) private var display
    @Environment(\.openWindow) private var openWindow

    private var status: PlanStatus { planStore.status }
    private var snapshot: UsageSnapshot { store.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            limits
            reconnectBanner

            if hasSecondarySections {
                Divider()
                creditsLine
                topOffenders
            }

            if snapshot.parseErrors > 0 {
                Label("\(snapshot.parseErrors) unparsed lines", systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(status.planLabel)
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.15)
            Spacer()
            ProvenanceBadge(status: status)
        }
    }

    // MARK: Limit gauges

    @ViewBuilder private var limits: some View {
        if let spend = status.spendLimit {
            SpendLimitGaugeRow(spend: spend)
        } else if status.windows.isEmpty {
            Label("\(DefaultPaths.formatTokens(snapshot.overall.total)) tokens total",
                  systemImage: "sum")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 13) {
                ForEach(status.windows, id: \.kind) { w in
                    LimitGaugeRow(name: windowName(w.kind), window: w)
                }
            }
        }
    }

    // MARK: Reconnect

    /// An explicit, always-visible way to re-establish the live connection when it
    /// has dropped — the manual escape hatch that was missing. Shown only when the
    /// live path reports an *actionable* problem: a dead token (`needsReauth`) or a
    /// transient/shape failure (`degraded`, the usual state right after wake).
    /// Deliberately hidden for `rateLimited` (retrying would only deepen the 429)
    /// and when live is healthy or switched off. `kick` — not `forceReconnect` —
    /// so the app comes forward and any Keychain re-auth prompt can surface.
    @ViewBuilder private var reconnectBanner: some View {
        if let message = reconnectMessage {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle").foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reconnect") { LiveLimitsActivation.kick(planStore, store) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The banner's copy, or `nil` when no reconnect affordance should appear.
    private var reconnectMessage: String? {
        switch status.liveHealth {
        case .needsReauth: return "Live sign-in expired."
        case .degraded:    return "Live limits disconnected."
        case .ok, .rateLimited, .none: return nil
        }
    }

    // MARK: Secondary sections

    private var hasSecondarySections: Bool {
        (status.credits?.enabled ?? false)
            || !store.breakdown(range: display.timeRange).byProject.isEmpty
    }

    /// Credit balance / spend, only when extra usage is enabled. Live values are
    /// real billed money (`.billed`); the grant-cache fallback is `.estimated`.
    @ViewBuilder private var creditsLine: some View {
        if let credits = status.credits, credits.enabled {
            HStack {
                Label("Credits", systemImage: "creditcard").font(.caption.weight(.medium))
                Spacer()
                Text(creditsText(credits))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Top projects for the selected range, honoring the $⇄tokens unit toggle.
    /// A faint share bar behind each row encodes its slice of usage relative to
    /// the busiest project; the percent column is its share of the grand total.
    @ViewBuilder private var topOffenders: some View {
        let all = store.breakdown(range: display.timeRange).byProject
        let rows = Array(all.prefix(5))
        if !rows.isEmpty {
            // Share math is token-based (the natural unit of "how much did this
            // project use"), regardless of the $⇄tokens display toggle.
            let grandTotal = all.reduce(0) { $0 + $1.totals.total }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "folder")
                    Text("Top projects").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(display.timeRange.displayName)
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 9)

                ForEach(Array(rows.enumerated()), id: \.element.key) { i, r in
                    ShareProjectRow(
                        name: r.key,
                        value: DefaultPaths.formatValue(totals: r.totals, costUSD: r.costUSD,
                                                        unit: display.unit),
                        share: grandTotal > 0 ? Double(r.totals.total) / Double(grandTotal) : 0,
                        tint: Dash.paletteColor(i))
                }
            }
        }
    }

    // MARK: Footer actions

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Details…") {
                openWindow(id: "details")
                // Menu-bar-only (.accessory) apps aren't frontmost, so a freshly
                // opened window would appear behind other apps — activate first.
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .keyboardShortcut("r")
                .help("Refresh now (⌘R)")
                .accessibilityLabel("Refresh now")
            Button {
                openWindow(id: "settings")
                // Menu-bar-only (.accessory) apps aren't frontmost, so activate so
                // the Settings window opens in front, not behind other apps.
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .font(.callout)
    }

    /// Manual refresh: force a live re-fetch (clearing any active poll backoff),
    /// re-scan events, and recompute the limit status. Clearing the throttle is
    /// what makes the button a real reconnect rather than a recompute of the
    /// last-held live reading.
    private func refresh() {
        LiveLimitsActivation.forceReconnect(planStore, store)
    }

    // MARK: Formatting

    private func creditsText(_ c: CreditsStatus) -> String {
        let left = MoneyFormat.string(minorUnits: c.balanceMinorUnits, currency: c.currency)
        guard let used = c.usedThisPeriodMinorUnits else { return "\(left) left" }
        return "\(left) left · \(MoneyFormat.string(minorUnits: used, currency: c.currency)) used"
    }

    private func windowName(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: return "5-hour"
        case .weekly:   return "Weekly"
        case .month:    return "This month"
        }
    }
}

/// One limit window rendered as a labelled progress gauge: name + reset on the
/// top line, a coloured bar below. The percent is coloured and bold (the number
/// you actually watch), and the whole row reads as one VoiceOver element with a
/// non-colour word for its state ("High"/"Critical").
struct LimitGaugeRow: View {
    let name: String
    let window: WindowStatus

    private var fraction: Double { min(1, max(0, window.percent ?? 0)) }
    private var color: Color { UsageColor.forPercent(window.percent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                if let reset = window.resetsAt {
                    Text(resetText(reset)).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                Text(percentText).font(.system(size: 13, weight: .bold))
                    .monospacedDigit().foregroundStyle(color)
            }
            GaugeBar(fraction: fraction, color: color)
            if let text = paceText {
                Text(text).font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) limit")
        .accessibilityValue(accessibilityValue)
    }

    private var percentText: String {
        guard let p = window.percent else { return "—" }
        return "\(Int((max(0, p) * 100).rounded()))%"
    }

    /// Only shown when the user is actually off-pace and we can name a moment —
    /// an on-track pace is the normal case and deserves no chrome.
    private var paceText: String? {
        guard let pace = window.pace, pace.status != .onTrack,
              let exhausts = pace.exhaustsAt else { return nil }
        let time = exhausts.formatted(date: .omitted, time: .shortened)
        let prefix = pace.provenance == .estimated ? "≈ at this pace" : "At this pace"
        return "\(prefix): limit reached \(time)"
    }

    private var accessibilityValue: String {
        var v = "\(percentText), \(UsageColor.label(window.percent))"
        if let reset = window.resetsAt {
            v += ", resets \(reset.formatted(.relative(presentation: .named)))"
        }
        if let text = paceText { v += ", \(text)" }
        return v
    }

    private func resetText(_ date: Date) -> String {
        "resets \(date.formatted(.relative(presentation: .named)))"
    }
}

/// The enterprise dollar spend-limit meter: "$11.70 of $70.00 spent" + a
/// coloured bar + "N% used", with a "Spend limit · Resets …" caption. Mirrors
/// `LimitGaugeRow` but in money rather than tokens.
struct SpendLimitGaugeRow: View {
    let spend: SpendLimitStatus

    private var fraction: Double { min(1, max(0, spend.percent)) }
    private var color: Color { UsageColor.forPercent(spend.percent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(spentText) of \(capText) spent")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 0)
                Text("\(percentText) used")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(color)
            }
            GaugeBar(fraction: fraction, color: color)
            HStack(spacing: 5) {
                Text("Spend limit").font(.system(size: 11)).foregroundStyle(.secondary)
                if let reset = spend.resetsAt {
                    Text("· Resets \(resetText(reset))")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spend limit")
        .accessibilityValue("\(spentText) of \(capText) spent, \(percentText) used, \(UsageColor.label(spend.percent))")
    }

    private var spentText: String { MoneyFormat.string(minorUnits: spend.spentMinorUnits, currency: spend.currency) }
    private var capText: String { MoneyFormat.string(minorUnits: spend.capMinorUnits, currency: spend.currency) }
    private var percentText: String { "\(Int((max(0, spend.percent) * 100).rounded()))%" }

    private func resetText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}

/// A flat, rounded 7pt limit bar: a faint track with a colour-filled portion.
/// Replaces `ProgressView` so the fill radius, height and track tint match the
/// refined popover exactly (green → amber → red carries the load).
struct GaugeBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule().fill(color)
                    .frame(width: max(0, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 7)
    }
}

/// One "Top projects" row: a muted per-project colour bar behind the row (its
/// share of total usage), the project name, its percent-of-total, and the value
/// in the chosen unit. The bar makes each project's spend scannable at a glance.
struct ShareProjectRow: View {
    let name: String
    let value: String
    /// Share of the grand total (0…1) — drives both the percent column and the
    /// width of the coloured bar, so bar length reads as "share of total usage".
    let share: Double
    /// Per-project categorical colour; the share bar renders as a muted wash of it
    /// so each project reads as a distinct band instead of one flat grey.
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 9) {
            Text(name)
                .font(.system(size: 12.5))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(shareText)
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 7)
                    .fill(tint.opacity(0.22))
                    .frame(width: max(0, geo.size.width * min(1, max(0, share))))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(value), \(shareText) of usage")
    }

    private var shareText: String {
        guard share > 0 else { return "0%" }
        if share < 0.01 { return "<1%" }
        return "\(Int((share * 100).rounded()))%"
    }
}

/// The colour-dot + word that states whether numbers are live, estimated, etc.
/// (spec §7 — provenance is always explicit). An orange dot flags estimates.
///
/// For live data it also states the sample's age when the endpoint is failing:
/// a stale-but-served live reading shows "Live · 12m ago" and its dot ambers
/// once past `staleAfter`, so a frozen number can never masquerade as current.
struct ProvenanceBadge: View {
    /// Takes the whole status, not just `provenance`/`liveAsOf`, because health
    /// (below) is an independent channel on the same value.
    let status: PlanStatus
    /// A live sample older than this reads as stale (amber dot). One poll is
    /// ~2 min; ~3 poll intervals of tolerance before we flag staleness.
    private let staleAfter: TimeInterval = 6 * 60

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(dotColor).frame(width: 6, height: 6)
            Text(text).font(.caption2)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Data source: \(accessibilityText)")
    }

    private var provenance: Provenance { status.provenance }

    /// Age of the live sample, only when it's old enough to be worth showing.
    private var age: TimeInterval? {
        guard provenance == .live, let liveAsOf = status.liveAsOf else { return nil }
        let seconds = Date().timeIntervalSince(liveAsOf)
        return seconds >= 60 ? seconds : nil
    }

    private var isStale: Bool { (age ?? 0) >= staleAfter }

    /// Health outranks age: "3d ago" on a dead token is worse than uninformative,
    /// it is a claim that the number is current.
    private var healthSuffix: String? {
        switch status.liveHealth {
        case .needsReauth:            return "reconnect"
        case .rateLimited:            return "rate-limited"
        case .degraded:               return "degraded"
        case .ok, .none:              return nil
        }
    }

    private var text: String {
        let base: String
        switch provenance {
        case .live:      base = age.map { "Live · \(Self.relativeAge($0))" } ?? "Live"
        case .estimated: base = "Estimated"
        case .derived:   base = "≈ cost"
        case .billed:    base = "Billed"
        case .measured:  base = "Measured"
        }
        guard let healthSuffix else { return base }
        return "\(base) · \(healthSuffix)"
    }

    private var accessibilityText: String {
        provenance == .live && isStale ? "\(text) (stale)" : text
    }

    private var dotColor: Color {
        // A reported health problem ambers the dot regardless of provenance —
        // even an .estimated badge should flag "reconnect" as actionable.
        if healthSuffix != nil { return .orange }
        switch provenance {
        case .live:            return isStale ? .orange : .green
        case .billed:          return .green
        case .estimated:       return .orange
        case .measured, .derived: return .secondary
        }
    }

    /// Compact "time ago": 5m / 3h / 2d.
    static func relativeAge(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        switch s {
        case ..<3_600:  return "\(max(1, s / 60))m ago"
        case ..<86_400: return "\(s / 3_600)h ago"
        default:        return "\(s / 86_400)d ago"
        }
    }
}

#Preview("Limit gauges") {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("Max 20×").font(.headline)
            Spacer()
            ProvenanceBadge(status: PlanStatus(
                kind: .subscription, planLabel: "Max 20×", windows: [], credits: nil,
                costUSD: nil, provenance: .live,
                liveAsOf: Date(timeIntervalSinceNow: -12 * 60), generatedAt: Date()))
        }
        LimitGaugeRow(name: "5-hour", window: WindowStatus(
            kind: .fiveHour, usedTokens: 38_000, capTokens: 100_000, percent: 0.38,
            resetsAt: Date(timeIntervalSinceNow: 7_200), provenance: .live))
        LimitGaugeRow(name: "Weekly", window: WindowStatus(
            kind: .weekly, usedTokens: 710_000, capTokens: 1_000_000, percent: 0.71,
            resetsAt: Date(timeIntervalSinceNow: 200_000), provenance: .live))
        LimitGaugeRow(name: "This month", window: WindowStatus(
            kind: .month, usedTokens: 980_000, capTokens: 1_000_000, percent: 0.98,
            resetsAt: nil, provenance: .estimated))
    }
    .padding(14).frame(width: 300)
}
