import SwiftUI
import AppKit
import CCTTCore

/// Brand artwork bundled with the app target. Loaded once from `Bundle.module`
/// (works under both `swift build` and `swift run`). `CCTTLogo` is the full app
/// icon (mascot + wordmark on a white rounded tile); `CCTTMark` is the mascot-only
/// tile for tight spots like the sidebar header.
enum Brand {
    static let logo = load("CCTTLogo")
    static let mark = load("CCTTMark")

    private static func load(_ name: String) -> Image {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let ns = NSImage(contentsOf: url) {
            return Image(nsImage: ns)
        }
        return Image(systemName: "gauge.with.dots.needle.67percent") // graceful fallback
    }
}

/// One selectable pane in the redesigned Settings window's sidebar.
enum SettingsSection: String, CaseIterable, Identifiable {
    case plan, live, alerts, display, data, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan:    return "Plan"
        case .live:    return "Live"
        case .alerts:  return "Alerts"
        case .display: return "Display"
        case .data:    return "Data"
        case .about:   return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .plan:    return "gauge.with.dots.needle.67percent"
        case .live:    return "dot.radiowaves.left.and.right"
        case .alerts:  return "bell.fill"
        case .display: return "slider.horizontal.3"
        case .data:    return "externaldrive.fill"
        case .about:   return "info.circle.fill"
        }
    }

    /// Icon tint — the design's per-section accent, mirroring System Settings'
    /// coloured rounded-rect glyphs.
    var tint: Color {
        switch self {
        case .plan:    return Color(red: 0.37, green: 0.36, blue: 0.90) // indigo #5E5CE6
        case .live:    return Color(red: 0.19, green: 0.69, blue: 0.30) // green  #30B14D
        case .alerts:  return Color(red: 1.00, green: 0.27, blue: 0.23) // red    #FF453A
        case .display: return Color(red: 0.04, green: 0.52, blue: 1.00) // blue   #0A84FF
        case .data:    return Color(red: 0.56, green: 0.56, blue: 0.58) // gray   #8E8E93
        case .about:   return Color(red: 0.20, green: 0.72, blue: 0.70) // teal   #34B8B3
        }
    }
}

/// The `⌘,` Settings scene, styled after **Claude Desktop**: a fully custom flush
/// two-pane layout (`HStack`) rather than a `NavigationSplitView`, so the sidebar
/// runs flush to the window edges and full-height under the floating traffic
/// lights instead of as an inset panel with a disconnected titlebar. The sidebar
/// is a real `NSVisualEffectView` (`.sidebar` material); the content is a native
/// grouped `Form`. All bindings read the shared stores.
struct SettingsView: View {
    @Environment(DisplayState.self) private var display
    @State private var selection: SettingsSection = .plan

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .frame(maxHeight: .infinity)
                .background(SidebarMaterial().ignoresSafeArea())

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        // The window uses `.hiddenTitleBar`; ignoring the top safe area lets both
        // panes run to the very top so the sidebar sits under the traffic lights,
        // which the header/title then clear with top padding.
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 720, minHeight: 460)
        .preferredColorScheme(display.appearance.colorScheme)
        // A menu-bar `.accessory` app must promote to `.regular` for its Settings
        // window to become a proper key window; revert to accessory on close.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppIdentityHeader()
                .padding(.horizontal, 14)
                .padding(.top, 34)          // clear the floating traffic lights
                .padding(.bottom, 14)

            Text("Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 5)

            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    SidebarRow(section: section, isSelected: selection == section) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 12)

            Divider().padding(.horizontal, 12)
            Text(versionLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
    }

    /// App name + version for the sidebar footer. Falls back to just the name when
    /// run unbundled (e.g. `swift run`), where the Info.plist version is absent.
    private var versionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "CCTT v\(AppVersion.string(bundleShort: v))"
    }

    // MARK: Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The About pane is a self-contained centred layout, so it skips the
            // top-left section title every other pane carries.
            if selection != .about {
                Text(selection.title)
                    .font(.system(size: 21, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 30)      // align with the sidebar header
                    .padding(.bottom, 2)
            }
            detailPane
        }
    }

    @ViewBuilder private var detailPane: some View {
        switch selection {
        case .plan:    PlanSettingsPane()
        case .live:    LiveSettingsPane()
        case .alerts:  AlertSettingsPane()
        case .display: DisplaySettingsPane()
        case .data:    DataSettingsPane()
        case .about:   AboutPane()
        }
    }
}

/// The flush, full-height translucent sidebar backing — a real `.sidebar`
/// visual-effect view, the same material AppKit source lists use.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - About

/// The About pane — a centred identity card: the gradient gauge tile, the app
/// name, its full title, a playful tagline, and the version.
private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Brand.logo
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

            Text("Claude Code Token Tracker")
                .font(.system(size: 17, weight: .semibold))

            Text("Keeping tabs on your token tab.")
                .font(.system(size: 13, weight: .regular))
                .italic()
                .foregroundStyle(.tertiary)

            Text(versionLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            Spacer()

            Text("A read-only observer of Claude Code's local usage — never writes "
                 + "to ~/.claude/.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 40)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "Version \(AppVersion.string(bundleShort: v))"
    }
}

// MARK: - Sidebar chrome

/// Compact branding anchor at the top of the sidebar (the Claude Desktop
/// account-chip position): gradient gauge tile + app name + live plan label.
private struct AppIdentityHeader: View {
    @Environment(PlanStore.self) private var planStore

    var body: some View {
        HStack(spacing: 9) {
            Brand.mark
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("CCTT")
                    .font(.system(size: 13, weight: .semibold))
                Text(planStore.plan.planLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// One sidebar navigation row — Claude Desktop metrics: small coloured icon tile,
/// 13pt label, tight padding. Selected rows take the system **accent** fill with a
/// white label (the native source-list idiom); hover is a subtle neutral tint.
private struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SidebarIcon(systemImage: section.systemImage, tint: section.tint)
                Text(section.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlight, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var highlight: Color {
        if isSelected { return .accentColor }
        if hovering { return Color.primary.opacity(0.05) }
        return .clear
    }
}

/// A coloured rounded-rect SF Symbol tile — sized for the compact Claude Desktop
/// sidebar (22pt tile, 12pt semibold white glyph).
private struct SidebarIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Plan

private struct PlanSettingsPane: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(PlanStore.self) private var planStore

    var body: some View {
        @Bindable var store = settingsStore
        Form {
            LabeledContent("Detected plan", value: detectedDescription)
            Picker("Plan mode", selection: $store.settings.manualPlanKind) {
                Text("Auto-detect").tag(PlanKind?.none)
                Text("Subscription").tag(PlanKind?.some(.subscription))
                Text("API (pay-as-you-go)").tag(PlanKind?.some(.api))
                Text("Enterprise").tag(PlanKind?.some(.enterprise))
            }

            if effectiveKind == .api {
                Section("API budget") {
                    OptionalDollarField(title: "Monthly budget",
                                        value: $store.settings.apiMonthlyBudgetUSD)
                }
            }
            if effectiveKind == .enterprise || effectiveKind == .subscription {
                Section("Manual caps (used when the tier is unknown)") {
                    OptionalTokenField(title: "5-hour cap", value: $store.settings.manualFiveHourCap)
                    OptionalTokenField(title: "Weekly cap", value: $store.settings.manualWeeklyCap)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Plan")
    }

    private var effectiveKind: PlanKind {
        settingsStore.settings.manualPlanKind ?? planStore.plan.kind
    }
    private var detectedDescription: String {
        let p = planStore.plan
        return p.source == .manual ? "\(p.planLabel) (overridden)" : p.planLabel
    }
}

// MARK: - Live limits

private struct LiveSettingsPane: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(PlanStore.self) private var planStore

    var body: some View {
        @Bindable var store = settingsStore
        Form {
            Section {
                Toggle("Fetch live limits", isOn: $store.settings.liveLimitsEnabled)
                Text("Uses Claude Code's existing sign-in (read from the Keychain) to "
                     + "fetch real limit percentages and reset times. The first fetch "
                     + "prompts for Keychain access. CCTT works fully on estimates if you "
                     + "leave this off.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Current source") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 7, height: 7)
                        Text(statusText).foregroundStyle(statusColor).fontWeight(.semibold)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Live")
    }

    private var isLive: Bool { planStore.status.provenance == .live }
    private var statusText: String {
        switch planStore.status.provenance {
        case .live:      return "Live"
        case .estimated: return "Estimated"
        case .derived:   return "Derived cost"
        case .billed:    return "Billed"
        case .measured:  return "Measured"
        }
    }
    private var statusColor: Color {
        isLive ? Color(red: 0.19, green: 0.69, blue: 0.30) : Color(red: 1.0, green: 0.58, blue: 0.0)
    }
}

// MARK: - Alerts

private struct AlertSettingsPane: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(NotificationManager.self) private var notifications

    var body: some View {
        @Bindable var store = settingsStore
        Form {
            Section {
                Toggle("Enable threshold notifications", isOn: $store.settings.alertsEnabled)
                    .onChange(of: store.settings.alertsEnabled) { _, on in
                        if on { Task { await notifications.requestAuthorization() } }
                    }
            }
            Section("Thresholds") {
                PercentStepper(title: "Warn at", value: warnBinding)
                PercentStepper(title: "Critical at", value: criticalBinding)
                Text("Applied to the 5-hour, weekly, and credit limits. Each fires once "
                     + "per crossing and re-arms when the window resets.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!store.settings.alertsEnabled)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Alerts")
    }

    // The UI edits two global thresholds; they map onto every window's array.
    private var warnBinding: Binding<Double> { thresholdBinding(index: 0, default: 0.8) }
    private var criticalBinding: Binding<Double> { thresholdBinding(index: 1, default: 0.95) }

    private func thresholdBinding(index: Int, default def: Double) -> Binding<Double> {
        Binding(
            get: { settingsStore.settings.thresholds.fiveHour[safe: index] ?? def },
            set: { newValue in
                var t = settingsStore.settings.thresholds
                t = t.setting(index: index, to: newValue)
                settingsStore.settings.thresholds = t
            })
    }
}

// MARK: - Display

private struct DisplaySettingsPane: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(DisplayState.self) private var display

    var body: some View {
        @Bindable var store = settingsStore
        @Bindable var display = display
        Form {
            Picker("Appearance", selection: $display.appearance) {
                ForEach(AppearanceOverride.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            Picker("Default unit", selection: $display.unit) {
                Text("Tokens").tag(DisplayUnit.tokens)
                Text("≈ Dollars").tag(DisplayUnit.dollars)
            }
            Section("Menu bar") {
                Toggle("Show usage percentage", isOn: $store.settings.showPercentInMenuBar)
                Text("When off, only the gauge icon shows in the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Detail tabs") {
                ForEach(DetailTab.allCases, id: \.id) { tab in
                    Toggle(tab.title, isOn: tabVisibility(tab))
                }
                Text("Turn off tabs you don't use to keep the detail window focused.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Display")
    }

    private func tabVisibility(_ tab: DetailTab) -> Binding<Bool> {
        Binding(
            get: { !settingsStore.settings.hiddenTabs.contains(tab.id) },
            set: { visible in
                if visible { settingsStore.settings.hiddenTabs.remove(tab.id) }
                else { settingsStore.settings.hiddenTabs.insert(tab.id) }
            })
    }
}

// MARK: - Data

private struct DataSettingsPane: View {
    @Environment(SettingsStore.self) private var settingsStore
    @State private var didResetCache = false

    var body: some View {
        @Bindable var store = settingsStore
        Form {
            Section("Projects directory") {
                LabeledContent("Path",
                               value: store.settings.projectsPathOverride ?? DefaultPaths.projectsDir.path)
                HStack {
                    Button("Choose…") { chooseDirectory() }
                    if store.settings.projectsPathOverride != nil {
                        Button("Use default") { store.settings.projectsPathOverride = nil }
                    }
                    Spacer()
                }
            }
            Section("Estimate tables") {
                LabeledContent("Cap table", value: CapTable.bundled.version)
                LabeledContent("Price table", value: PriceTable.bundled.version)
            }
            Section {
                Button("Reset offset cache") {
                    try? FileManager.default.removeItem(at: DefaultPaths.offsetCacheURL)
                    didResetCache = true
                }
                if didResetCache {
                    Text("Cache cleared. It rebuilds on the next scan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Data")
    }

    /// Opens a directory picker; on confirm, stores the chosen path as the
    /// override. macOS-idiomatic replacement for typing a filesystem path.
    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the Claude Code projects directory"
        panel.directoryURL = URL(fileURLWithPath:
            settingsStore.settings.projectsPathOverride ?? DefaultPaths.projectsDir.path)
        if panel.runModal() == .OK, let url = panel.url {
            settingsStore.settings.projectsPathOverride = url.path
        }
    }
}

// MARK: - Small reusable controls

private struct PercentStepper: View {
    let title: String
    @Binding var value: Double
    var body: some View {
        Stepper(value: $value, in: 0.05...1.0, step: 0.05) {
            LabeledContent(title, value: "\(Int((value * 100).rounded()))%")
        }
    }
}

private struct OptionalDollarField: View {
    let title: String
    @Binding var value: Double?
    var body: some View {
        TextField(title, value: $value, format: .currency(code: "USD"))
            .textFieldStyle(.roundedBorder)
    }
}

private struct OptionalTokenField: View {
    let title: String
    @Binding var value: Int?
    var body: some View {
        TextField(title, value: $value, format: .number)
            .textFieldStyle(.roundedBorder)
    }
}

private extension Array where Element == Double {
    subscript(safe index: Int) -> Double? { indices.contains(index) ? self[index] : nil }
}

private extension AlertThresholds {
    /// Returns a copy with `index` set to `value` across all windows (the UI
    /// exposes shared warn/critical thresholds).
    func setting(index: Int, to value: Double) -> AlertThresholds {
        func set(_ arr: [Double]) -> [Double] {
            var a = arr
            while a.count <= index { a.append(0.8) }
            a[index] = value
            return a
        }
        return AlertThresholds(fiveHour: set(fiveHour), weekly: set(weekly), credits: set(credits))
    }
}
