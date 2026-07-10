import AppKit
import CCTTCore
import Sparkle

/// Concrete `SoftwareUpdating` backed by Sparkle's standard controller. Only
/// instantiated when running as a real `.app` bundle (see `CCTTApp`); dev runs
/// use `DisabledUpdater` instead.
@MainActor
@Observable
// The `@MainActor` on the conformance is load-bearing, not redundant: it makes
// this an isolated conformance so `any SoftwareUpdating` formed from a
// `SparkleUpdater` is usable from MainActor contexts, while `DisabledUpdater`
// keeps a plain non-isolated conformance. Removing it breaks the build.
final class SparkleUpdater: @MainActor SoftwareUpdating {
    private let controller: SPUStandardUpdaterController

    init() {
        // `startingUpdater: true` begins the scheduled background check per the
        // Info.plist `SUEnableAutomaticChecks`/`SUFeedURL` keys.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        // As an `.accessory` app we aren't frontmost; activate so Sparkle's
        // update dialog appears in front rather than behind other apps.
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }
}
