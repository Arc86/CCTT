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

    var body: some Scene {
        MenuBarExtra {
            PopoverView(snapshot: store.snapshot)
        } label: {
            // Headline for Plan 1: compact total token count. Plan 2 swaps this
            // for "% of limit used".
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(DefaultPaths.formatTokens(store.snapshot.overall.total))
                // Initial scan + periodic refresh (FSEvents watch added in a later
                // plan). Verified in this environment: a `.task` loop tied to the
                // label view's lifecycle reliably drives repeated `store.refresh()`
                // calls and updates the rendered NSStatusItem text. An AppDelegate
                // `@Published` tick bridged via `.onChange(of:)` on the Scene (and
                // on this same view) was tried first per the original design but
                // never fired in manual verification — the status item stayed
                // frozen at the initial "0" — so that approach was replaced with
                // this one. See task-8-report.md for verification evidence.
                .task {
                    while !Task.isCancelled {
                        store.refresh()
                        try? await Task.sleep(for: .seconds(20))
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Makes the app a menu-bar-only accessory (no Dock icon, no menu bar app menu).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
