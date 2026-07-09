import SwiftUI
import CCTTCore

/// The `⌘,` Settings scene. Conventional macOS multi-pane `TabView`; each pane
/// is a `Form`. Reads the shared stores from the environment.
struct SettingsView: View {
    var body: some View {
        TabView {
            PlanSettingsPane()
                .tabItem { Label("Plan", systemImage: "person.crop.circle") }
            LiveSettingsPane()
                .tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
            AlertSettingsPane()
                .tabItem { Label("Alerts", systemImage: "bell") }
            DisplaySettingsPane()
                .tabItem { Label("Display", systemImage: "slider.horizontal.3") }
            DataSettingsPane()
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 460)
        .frame(minHeight: 340)
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
        .padding()
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
                LabeledContent("Status", value: provenanceDescription)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var provenanceDescription: String {
        switch planStore.status.provenance {
        case .live:      return "Live"
        case .estimated: return "Estimated (tier cap table)"
        case .derived:   return "Derived cost"
        case .billed:    return "Billed"
        case .measured:  return "Measured"
        }
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
        .padding()
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
            Picker("Default unit", selection: $display.unit) {
                Text("Tokens").tag(DisplayUnit.tokens)
                Text("≈ Dollars").tag(DisplayUnit.dollars)
            }
            Section("Detail tabs") {
                ForEach(DetailTab.allCases, id: \.id) { tab in
                    Toggle(tab.title, isOn: tabVisibility(tab))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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
                TextField("Override path (blank = default)",
                          text: pathBinding).textFieldStyle(.roundedBorder)
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
        .padding()
    }

    private var pathBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.projectsPathOverride ?? "" },
            set: { settingsStore.settings.projectsPathOverride = $0.isEmpty ? nil : $0 })
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
