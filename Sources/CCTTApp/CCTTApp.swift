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
    @State private var planStore = PlanStore(
        configURL: DefaultPaths.configURL,
        clock: { Date() }
    )

    var body: some Scene {
        MenuBarExtra {
            PopoverView(snapshot: store.snapshot, status: planStore.status)
        } label: {
            // Headline: "% of limit used" (Plan 2), falling back to the token
            // total when the plan/cap is unknown.
            Image(systemName: "gauge.with.dots.needle.33percent")
                .foregroundStyle(glanceColor(planStore.status.headlinePercent))
            Text(DefaultPaths.formatPercent(planStore.status,
                                            fallbackTokens: store.snapshot.overall.total))
                // Initial scan + periodic refresh. Verified in Plan 1: a `.task`
                // loop tied to the label view reliably drives repeated refreshes
                // and updates the NSStatusItem text. Plan 4 replaces the timer
                // with an FSEvents watch.
                .task {
                    while !Task.isCancelled {
                        store.refresh()
                        await planStore.refresh(snapshot: store.snapshot)
                        try? await Task.sleep(for: .seconds(20))
                    }
                }
        }
        .menuBarExtraStyle(.window)
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
