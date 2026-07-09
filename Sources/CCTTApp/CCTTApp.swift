import SwiftUI
import AppKit
import CCTTCore

@main
struct CCTTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = UsageStore(
        scanner: Ingestor(projectsDir: DefaultPaths.projectsDir,
                          cacheURL: DefaultPaths.offsetCacheURL),
        clock: { Date() }
    )
    // Live limits are opt-in: the provider is gated on the persisted setting, so
    // no Keychain/network access happens until the user enables it. Plan/budget/
    // cap overrides are read from the same persisted settings each refresh.
    @State private var planStore = PlanStore(
        configURL: DefaultPaths.configURL,
        provider: GatedLiveLimitProvider(
            wrapping: NetworkLiveLimitProvider(),
            isEnabled: { AppSettingsStorage.load().liveLimitsEnabled }),
        settingsProvider: { AppSettingsStorage.load() },
        clock: { Date() }
    )
    @State private var display = DisplayState()
    @State private var settingsStore = SettingsStore()
    @State private var notifications = NotificationManager()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
                .environment(planStore)
                .environment(display)
                .environment(settingsStore)
        } label: {
            MenuBarLabel()
                .environment(store)
                .environment(planStore)
                .environment(settingsStore)
                .environment(notifications)
        }
        .menuBarExtraStyle(.window)

        // Resizable detail window opened from the popover's "Open Details…".
        Window("CCTT Details", id: "details") {
            DetailView()
                .environment(store)
                .environment(planStore)
                .environment(display)
                .environment(settingsStore)
        }
        .windowResizability(.contentMinSize)

        // First-launch onboarding (opened once until completed).
        Window("Welcome to CCTT", id: "onboarding") {
            OnboardingView()
                .environment(settingsStore)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(settingsStore)
                .environment(planStore)
                .environment(display)
                .environment(notifications)
        }
    }
}

/// The menu-bar item: headline "% used" plus the periodic refresh loop that
/// drives usage aggregation, limit computation, and threshold notifications.
struct MenuBarLabel: View {
    @Environment(UsageStore.self) private var store
    @Environment(PlanStore.self) private var planStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // A `.task` tied to the label reliably drives repeated refreshes and
        // updates the NSStatusItem (verified in Plan 1).
        Image(systemName: "gauge.with.dots.needle.33percent")
            .foregroundStyle(glanceColor(planStore.status.headlinePercent))
        Text(DefaultPaths.formatPercent(planStore.status,
                                        fallbackTokens: store.snapshot.overall.total))
            .task {
                if !OnboardingState.hasOnboarded() {
                    openWindow(id: "onboarding")
                    NSApp.activate(ignoringOtherApps: true)
                }
                while !Task.isCancelled {
                    store.refresh()
                    await planStore.refresh(snapshot: store.snapshot)
                    notifications.process(status: planStore.status,
                                          settings: settingsStore.settings)
                    try? await Task.sleep(for: .seconds(20))
                }
            }
    }

    /// Green → amber → red as the constraining limit approaches (spec §8.1).
    private func glanceColor(_ percent: Double?) -> Color {
        guard let p = percent else { return .secondary }
        switch p {
        case ..<0.8:  return .green
        case ..<0.95: return .orange
        default:      return .red
        }
    }
}

/// Makes the app a menu-bar-only accessory (no Dock icon, no menu bar app menu).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
