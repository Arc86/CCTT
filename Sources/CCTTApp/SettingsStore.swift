import Foundation
import Observation
import CCTTCore

/// Persistence bridge for `AppSettings`. Kept as a plain enum so the same
/// (thread-safe `UserDefaults`) read can be used from the `PlanStore`'s
/// `@Sendable` settings closure without capturing a main-actor object.
enum AppSettingsStorage {
    static let key = "cctt.appSettings.v1"

    static func load(_ defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    static func save(_ settings: AppSettings, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}

/// Observable, main-actor holder of `AppSettings` for the Settings UI. Every
/// mutation is persisted immediately, so the `PlanStore` closure reading
/// `AppSettingsStorage.load()` always sees the latest values.
@MainActor
@Observable
final class SettingsStore {
    var settings: AppSettings {
        didSet { AppSettingsStorage.save(settings, to: defaults) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = AppSettingsStorage.load(defaults)
    }
}
