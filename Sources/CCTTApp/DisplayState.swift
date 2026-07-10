import Foundation
import Observation
import SwiftUI
import CCTTCore

/// The detail window's appearance override. Defaults to `.system` so CCTT follows
/// macOS light/dark like a good citizen, but the design's light/dark toggle is
/// honoured for users who want to pin one.
enum AppearanceOverride: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    var label: String {
        switch self { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" }
    }
    var systemImage: String {
        switch self { case .system: return "circle.lefthalf.filled"
                      case .light:  return "sun.max"
                      case .dark:   return "moon" }
    }
}

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
    var appearance: AppearanceOverride {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let unit = "display.unit"
        static let range = "display.timeRange"
        static let appearance = "display.appearance"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // didSet does not fire for assignments inside init, so this reads-only.
        self.unit = DisplayUnit(storageKey: defaults.string(forKey: Keys.unit))
        self.timeRange = TimeRange(storageKey: defaults.string(forKey: Keys.range))
        self.appearance = AppearanceOverride(rawValue: defaults.string(forKey: Keys.appearance) ?? "")
            ?? .system
    }
}
