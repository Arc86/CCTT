import SwiftUI
import AppKit
import CCTTCore

@main
struct CCTTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // The event store makes historical usage durable across restarts; the offset
    // cache URL lets the store self-heal if that log ever vanishes out from under
    // a still-advanced offset cache.
    @State private var store = UsageStore(
        scanner: Ingestor(projectsDir: DefaultPaths.projectsDir,
                          cacheURL: DefaultPaths.offsetCacheURL),
        eventStore: EventStore(url: DefaultPaths.eventStoreURL),
        titleStore: SessionTitleStore(url: DefaultPaths.sessionTitleStoreURL),
        offsetCacheURL: DefaultPaths.offsetCacheURL,
        clock: { Date() }
    )
    // Live limits are opt-in: the provider is gated on the persisted setting, so
    // no Keychain/network access happens until the user enables it. Plan/budget/
    // cap overrides are read from the same persisted settings each refresh.
    @State private var planStore = PlanStore(
        configURL: DefaultPaths.configURL,
        provider: GatedLiveLimitProvider(
            wrapping: StickyLiveLimitProvider(
                wrapping: NetworkLiveLimitProvider(
                    // Cache the OAuth token in-process so the Keychain is read only
                    // when the token nears expiry, not on every 120s poll — that
                    // repeated read is what re-prompted the user "from time to time".
                    credentials: CachingCredentialsSource(wrapping: KeychainCredentialsSource())),
                cacheURL: DefaultPaths.liveLimitsCacheURL),
            isEnabled: { AppSettingsStorage.load().liveLimitsEnabled }),
        settingsProvider: { AppSettingsStorage.load() },
        clock: { Date() }
    )
    @State private var display = DisplayState()
    @State private var settingsStore = SettingsStore()
    @State private var notifications = NotificationManager()
    // Live auto-updater only when running as a real `.app`; dev runs stay inert.
    @State private var updater: any SoftwareUpdating =
        AppBundling.isBundled(Bundle.main.bundleURL) ? SparkleUpdater() : DisabledUpdater()
    private let loginItem: any LoginItemControlling = SystemLoginItem()

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
                .environment(store)
                .environment(planStore)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)

        // A regular `Window` (not the `Settings {}` scene) opened via
        // `openWindow(id: "settings")` from the popover gear (⌘,). `.hiddenTitleBar`
        // drops the classic horizontal titlebar strip so the sidebar runs flush to
        // the very top with the traffic lights floating over it — the unified
        // Claude Desktop idiom, instead of a titlebar disconnected from the panel.
        Window("Settings", id: "settings") {
            SettingsView()
                .environment(settingsStore)
                .environment(store)
                .environment(planStore)
                .environment(display)
                .environment(notifications)
                .environment(\.softwareUpdater, updater)
                .environment(\.loginItem, loginItem)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 780, height: 600)
        .defaultPosition(.center)
        // As an `.accessory` app there is no app menu, so the standard editing
        // shortcuts (⌘X/C/V/A) would be absent in the Settings text fields.
        // Installing the text-editing command group restores them.
        .commands {
            TextEditingCommands()
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
        // updates the NSStatusItem (verified in Plan 1). The gauge glyph now
        // tracks the real load so the icon alone reads at a glance.
        let percent = planStore.status.headlinePercent
        // The gauge glyph is always shown and carries the refresh loop; the "%
        // used" text is optional (Settings ▸ Display), so it can never be the
        // sole host of the `.task`.
        Image(systemName: UsageColor.gaugeSymbol(percent))
            .foregroundStyle(UsageColor.forPercent(percent))
            .accessibilityLabel("Claude Code usage: \(DefaultPaths.formatPercent(planStore.status, fallbackTokens: store.snapshot.overall.total)), \(UsageColor.label(percent))")
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
                    // Publish the status for external consumers (opt-in).
                    let writer = UsageExportWriter()
                    if settingsStore.settings.exportEnabled {
                        try? writer.write(planStore.status)
                    }
                    // The live rate-limit endpoint 429s under frequent polling, so
                    // PlanStore backs the interval off on failure and snaps it back
                    // to 120s on success (see PollSchedule).
                    try? await Task.sleep(for: .seconds(planStore.nextPollInterval))
                }
            }
        if settingsStore.settings.showPercentInMenuBar {
            Text(DefaultPaths.formatPercent(planStore.status,
                                            fallbackTokens: store.snapshot.overall.total))
                // The gauge Image's accessibilityLabel already speaks the percent;
                // without this VoiceOver reads it twice.
                .accessibilityHidden(true)
        }
    }
}

/// Makes the app a menu-bar-only accessory (no Dock icon, no menu bar app menu).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // No Dock icon as an accessory, but the Settings window promotes the app
        // to `.regular`, where ⌘-Tab and the Dock show this icon. Use the
        // pre-rounded squircle tile (macOS doesn't round Dock icons for us) so it
        // matches the bundle's AppIcon.icns instead of a flat square.
        if let url = AppResources.bundle.url(forResource: "AppIcon-1024", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
}

/// Fire an immediate live-limit refresh the instant the user opts in, so the
/// Keychain access prompt appears in direct response to their click instead of
/// up to ~120s later on the next background poll tick (the reason first-launch
/// opt-in looked like it did nothing). Bringing the app forward makes the modal
/// prompt surface even though CCTT is an `LSUIElement` accessory.
@MainActor
enum LiveLimitsActivation {
    static func kick(_ planStore: PlanStore, _ usage: UsageStore) {
        NSApp.activate(ignoringOtherApps: true)
        Task { await planStore.refresh(snapshot: usage.snapshot) }
    }
}
