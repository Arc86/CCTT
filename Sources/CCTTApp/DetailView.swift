import SwiftUI
import CCTTCore

/// One selectable item in the detail window's sidebar: a breakdown tab, or the
/// separate Plan pane.
enum SidebarItem: Hashable, Identifiable {
    case tab(DetailTab)
    case plan
    var id: String { switch self { case .tab(let t): return t.id; case .plan: return "plan" } }
}

/// The resizable detail window, redesigned as a sidebar dashboard (CCTT Insight
/// Dashboard): a Breakdowns + Plan sidebar drives a hero-topped detail pane with a
/// global range + unit toolbar. Reads the shared stores from the environment.
struct DetailView: View {
    @Environment(UsageStore.self) private var store
    @Environment(PlanStore.self) private var planStore
    @Environment(DisplayState.self) private var display
    @Environment(SettingsStore.self) private var settingsStore
    @State private var selection: SidebarItem? = .tab(.projects)
    // Owned here so the Context tab's drill-down selection persists across tab
    // switches even though that tab's view is rebuilt each time it's shown.
    @State private var contextSelection: String?

    private func isVisible(_ tab: DetailTab) -> Bool {
        !settingsStore.settings.hiddenTabs.contains(tab.id)
    }

    /// Visible breakdown tabs in display order — drives the ⌘-number shortcuts and
    /// the fallback used when the selected tab gets hidden in Settings.
    private var visibleTabs: [DetailTab] { DetailTab.allCases.filter(isVisible) }

    /// Every sidebar destination in order (visible breakdowns, then Plan).
    private var sidebarItems: [SidebarItem] { visibleTabs.map(SidebarItem.tab) + [.plan] }

    /// The resolved current destination (never nil once a selection exists).
    private var current: SidebarItem { selection ?? sidebarItems.first ?? .plan }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 178, ideal: 196, max: 240)
        } detail: {
            detailPane
        }
        .frame(minWidth: 760, minHeight: 540)
        // Drives both the SwiftUI content *and* the window's `NSAppearance`, so the
        // AppKit toolbar chrome (the range/unit segmented controls) follows the
        // light/dark override rather than getting stuck at the system appearance.
        .preferredColorScheme(display.appearance.colorScheme)
        .background(tabHotkeys)
        .onChange(of: visibleTabs) { repairSelectionIfHidden() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        @Bindable var display = display
        return VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Breakdowns") {
                    ForEach(visibleTabs) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(SidebarItem.tab(tab))
                    }
                }
                Section("Plan") {
                    Label("Plan usage", systemImage: "gauge.with.dots.needle.67percent")
                        .tag(SidebarItem.plan)
                }
            }
            .listStyle(.sidebar)

            Divider()
            Picker("Appearance", selection: $display.appearance) {
                ForEach(AppearanceOverride.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(8)
            .help("Window appearance")
        }
    }

    // MARK: Detail pane

    private var detailPane: some View {
        @Bindable var display = display
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !isPlan {
                    HeroHeader(breakdown: breakdown, delta: store.tokenDelta(range: display.timeRange),
                               sparkValues: sparkValues, unit: display.unit)
                }
                paneContent
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(navTitle)
        .navigationSubtitle(subhead)
        .toolbar {
            if !isPlan {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Range", selection: $display.timeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .help("Time range shown across every tab")
                }
            }
            if unitVisible {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Unit", selection: $display.unit) {
                        ForEach(DisplayUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .help("Show measured tokens or ≈ derived cost")
                }
            }
        }
    }

    /// The body for the current destination. Sessions/Context derive their data only
    /// while shown; the store's builders are memoized by `dataVersion`.
    @ViewBuilder private var paneContent: some View {
        switch current {
        case .tab(.projects):
            ProjectsBody(breakdown: breakdown, unit: display.unit)
        case .tab(.models):
            ModelsBody(breakdown: breakdown, unit: display.unit)
        case .tab(.agents):
            AgentsBody(breakdown: breakdown, unit: display.unit)
        case .tab(.sessions):
            SessionsBody(timeline: store.timeline(range: display.timeRange),
                         hourly: store.hourlyProfile(range: display.timeRange),
                         sessions: store.sessions(range: display.timeRange),
                         unit: display.unit, rangeName: longRangeName(display.timeRange))
        case .tab(.context):
            ContextBody(summaries: store.contextSummaries(range: display.timeRange),
                        seriesProvider: { store.contextSeries(sessionId: $0) },
                        selected: $contextSelection)
        case .plan:
            PlanBody(status: planStore.status, breakdown: breakdown)
        }
    }

    // MARK: Derived UI state

    private var breakdown: Breakdown { store.breakdown(range: display.timeRange) }

    private var isPlan: Bool { current == .plan }

    /// Unit toggle hides on Context (measured only) and Plan (no per-unit view).
    private var unitVisible: Bool {
        switch current { case .tab(.context), .plan: return false; default: return true }
    }

    private var navTitle: String {
        switch current { case .tab(let t): return t.navTitle; case .plan: return "Plan usage" }
    }

    private var subhead: String {
        switch current {
        case .tab:
            return "\(longRangeName(display.timeRange)) · "
                + (display.unit == .dollars ? "≈ cost" : "measured tokens")
        case .plan:
            return "\(planStore.status.planLabel) · rolling usage windows"
        }
    }

    private var sparkValues: [Double] {
        store.timeline(range: display.timeRange).map {
            display.unit == .dollars ? $0.costUSD : Double($0.totals.total)
        }
    }

    private func repairSelectionIfHidden() {
        if case .tab(let t) = current, !isVisible(t) {
            selection = sidebarItems.first ?? .plan
        }
    }

    /// Hidden ⌘1…⌘N buttons that jump to the Nth sidebar destination, so the
    /// shortcuts work window-wide without cluttering the UI (an accessory app has no
    /// menu bar to host commands, so we bind them here).
    private var tabHotkeys: some View {
        ForEach(Array(sidebarItems.prefix(9).enumerated()), id: \.element) { index, item in
            Button("") { selection = item }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
    }
}
