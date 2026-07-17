import SwiftUI

/// Single source of truth for the green → amber → red usage treatment shared by
/// the menu-bar icon, the popover gauges, and their VoiceOver descriptions, so
/// the whole app agrees on what "getting close to the limit" looks and reads
/// like (spec §8.1). Meaning is never carried by colour alone — every colour has
/// a matching `label(_:)` word for redundancy (a11y guide: icon + label).
///
/// These thresholds are **fixed and deliberately do not follow the user's
/// configurable alert thresholds** (`AppSettings.thresholds`). The two answer
/// different questions: the colour is a shared visual language, and the words
/// pinned to it ("OK"/"High"/"Critical") must mean the same thing for everyone,
/// whereas an alert threshold is a personal choice about when to be interrupted.
/// Making the colour user-relative would make "Critical" mean different things to
/// different people. ClaudeMeter draws the same line, for the same reason.
///
/// Note `gaugeSymbol`'s 0.5/0.85 split is *not* a competing status threshold: it
/// selects a needle position (33/67/100%), i.e. a magnitude, not a state.
enum UsageColor {
    /// Bucket a 0…1+ fraction into the headline colour. `nil` (unknown) is neutral.
    static func forPercent(_ percent: Double?) -> Color {
        guard let p = percent else { return .secondary }
        switch p {
        case ..<0.8:  return .green
        case ..<0.95: return .orange
        default:      return .red
        }
    }

    /// The word that goes with the colour, for VoiceOver and non-colour readers.
    static func label(_ percent: Double?) -> String {
        guard let p = percent else { return "unknown" }
        switch p {
        case ..<0.8:  return "OK"
        case ..<0.95: return "High"
        default:      return "Critical"
        }
    }

    /// The discrete needle-gauge SF Symbol that best matches the current load.
    /// Discrete variants (all shipping symbols) keep the menu-bar glyph legible
    /// at status-item size where a variable-value needle would be muddy.
    static func gaugeSymbol(_ percent: Double?) -> String {
        guard let p = percent else { return "gauge.with.dots.needle.33percent" }
        switch p {
        case ..<0.5:  return "gauge.with.dots.needle.33percent"
        case ..<0.85: return "gauge.with.dots.needle.67percent"
        default:      return "gauge.with.dots.needle.100percent"
        }
    }
}
