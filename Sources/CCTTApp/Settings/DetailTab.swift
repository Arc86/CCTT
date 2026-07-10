import Foundation

/// Stable identity for each detail-window tab, so Settings can toggle tabs off
/// (persisted in `AppSettings.hiddenTabs`) and `DetailView` can honour it.
enum DetailTab: String, CaseIterable, Identifiable {
    case projects, models, agents, sessions, context

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: return "Projects"
        case .models:   return "Models"
        case .agents:   return "Agents"
        case .sessions: return "Sessions"
        case .context:  return "Context"
        }
    }

    /// The detail window's navigation subtitle context for this breakdown.
    var navTitle: String {
        switch self {
        case .projects: return "Projects"
        case .models:   return "Models"
        case .agents:   return "Agents, skills & plugins"
        case .sessions: return "Sessions & timeline"
        case .context:  return "Context windows"
        }
    }

    /// SF Symbol shown in the sidebar (native equivalents of the design's glyphs).
    var systemImage: String {
        switch self {
        case .projects: return "folder"
        case .models:   return "cube"
        case .agents:   return "sparkles"
        case .sessions: return "clock"
        case .context:  return "rectangle.stack"
        }
    }
}
