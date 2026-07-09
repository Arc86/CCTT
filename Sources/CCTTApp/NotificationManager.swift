import Foundation
import Observation
import UserNotifications
import CCTTCore

/// Delivers edge-triggered threshold alerts. All the decision logic lives in the
/// pure `AlertEngine`; this shell only owns permission, the persisted
/// `AlertState`, and the `UNUserNotificationCenter` side effect.
///
/// Notification-center access is guarded on a real bundle identifier so the app
/// stays crash-free when launched via `swift run` (an un-bundled executable).
@MainActor
@Observable
final class NotificationManager {
    private(set) var authorized = false

    private var state: AlertState
    private let defaults: UserDefaults
    private static let stateKey = "cctt.alertState.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.stateKey),
           let restored = try? JSONDecoder().decode(AlertState.self, from: data) {
            state = restored
        } else {
            state = AlertState()
        }
    }

    /// True only inside a real app bundle; `UNUserNotificationCenter` traps otherwise.
    var isSupported: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() async {
        guard isSupported else { return }
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        authorized = granted ?? false
    }

    /// Evaluate thresholds against the latest status; fire notifications for any
    /// newly-crossed thresholds and persist the (edge-trigger) state either way.
    func process(status: PlanStatus, settings: AppSettings) {
        guard settings.alertsEnabled else { return }
        let percents = AlertEngine.percents(from: status)
        let result = AlertEngine.evaluate(percents: percents,
                                          thresholds: settings.thresholds, state: state)
        state = result.state
        persist()
        guard isSupported else { return }
        result.alerts.forEach(fire)
    }

    // MARK: - Private

    private func fire(_ alert: Alert) {
        let content = UNMutableNotificationContent()
        content.title = "\(Self.name(alert.window)) usage at \(pct(alert.threshold))"
        content.body = "You're at \(pct(alert.percent)) of your \(Self.name(alert.window)) limit."
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }

    private func pct(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }

    private static func name(_ window: AlertWindow) -> String {
        switch window {
        case .fiveHour: return "5-hour"
        case .weekly:   return "weekly"
        case .credits:  return "credit"
        }
    }
}
