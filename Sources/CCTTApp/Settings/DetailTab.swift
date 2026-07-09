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
}
