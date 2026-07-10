import CCTTCore
import ServiceManagement

/// `LoginItemControlling` backed by `SMAppService.mainApp`. The system's
/// `status` is the single source of truth — no mirrored setting to drift.
/// Unbundled runs report `status == .notFound`, so `isEnabled` is false and
/// `setEnabled` throws; the UI disables the control in that case anyway.
struct SystemLoginItem: LoginItemControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
