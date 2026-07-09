import Foundation
import Observation
import CCTTCore

/// User-facing display preferences shared by the popover and detail window.
/// Backed by `UserDefaults` so selections survive relaunch. The Core enums stay
/// pure; only this bridge touches persistence (encoding via their `storageKey`).
@MainActor
@Observable
final class DisplayState {
    var unit: DisplayUnit {
        didSet { defaults.set(unit.storageKey, forKey: Keys.unit) }
    }
    var timeRange: TimeRange {
        didSet { defaults.set(timeRange.storageKey, forKey: Keys.range) }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let unit = "display.unit"
        static let range = "display.timeRange"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // didSet does not fire for assignments inside init, so this reads-only.
        self.unit = DisplayUnit(storageKey: defaults.string(forKey: Keys.unit))
        self.timeRange = TimeRange(storageKey: defaults.string(forKey: Keys.range))
    }
}
