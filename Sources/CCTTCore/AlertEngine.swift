import Foundation

/// A limit window that can raise a threshold alert.
public enum AlertWindow: String, Sendable, Equatable, Codable, CaseIterable {
    case fiveHour, weekly, credits
}

/// User-configured alert thresholds (fractions, e.g. 0.8 = 80%) per window.
public struct AlertThresholds: Sendable, Equatable, Codable {
    public var fiveHour: [Double]
    public var weekly: [Double]
    public var credits: [Double]

    public init(fiveHour: [Double] = [0.8, 0.95],
                weekly: [Double] = [0.8, 0.95],
                credits: [Double] = [0.8, 0.95]) {
        self.fiveHour = fiveHour; self.weekly = weekly; self.credits = credits
    }

    public static let `default` = AlertThresholds()

    public func values(for window: AlertWindow) -> [Double] {
        switch window {
        case .fiveHour: return fiveHour
        case .weekly:   return weekly
        case .credits:  return credits
        }
    }
}

/// One fired alert: a window crossed a threshold upward.
public struct Alert: Sendable, Equatable {
    public let window: AlertWindow
    public let threshold: Double
    public let percent: Double
    public init(window: AlertWindow, threshold: Double, percent: Double) {
        self.window = window; self.threshold = threshold; self.percent = percent
    }
}

/// Persisted edge-trigger state: which thresholds are currently *latched*
/// (already fired, not yet re-armed) per window. Stored as basis points so it is
/// exactly Codable and free of float-key hazards. Survives app restarts.
public struct AlertState: Sendable, Equatable, Codable {
    private var latched: [String: [Int]]
    public init() { latched = [:] }

    fileprivate func isLatched(_ window: AlertWindow, _ threshold: Double) -> Bool {
        latched[window.rawValue]?.contains(Self.bp(threshold)) ?? false
    }
    fileprivate mutating func latch(_ window: AlertWindow, _ threshold: Double) {
        latched[window.rawValue, default: []].append(Self.bp(threshold))
    }
    fileprivate mutating func rearm(_ window: AlertWindow, _ threshold: Double) {
        latched[window.rawValue]?.removeAll { $0 == Self.bp(threshold) }
    }
    private static func bp(_ f: Double) -> Int { Int((f * 10_000).rounded()) }
}

/// Pure, edge-triggered alert evaluation. Given the current per-window percents,
/// the configured thresholds, and the prior latch state, returns the alerts to
/// fire now plus the updated state to persist.
public enum AlertEngine {

    public static func evaluate(
        percents: [AlertWindow: Double],
        thresholds: AlertThresholds,
        state: AlertState
    ) -> (alerts: [Alert], state: AlertState) {
        var state = state
        var alerts: [Alert] = []

        for window in AlertWindow.allCases {
            guard let percent = percents[window] else { continue }
            for threshold in thresholds.values(for: window).sorted() {
                let latched = state.isLatched(window, threshold)
                if percent >= threshold, !latched {
                    alerts.append(Alert(window: window, threshold: threshold, percent: percent))
                    state.latch(window, threshold)
                } else if percent < threshold, latched {
                    state.rearm(window, threshold)   // window reset → arm for next cycle
                }
            }
        }
        return (alerts, state)
    }

    /// Extracts the per-window percents an alert evaluation needs from a
    /// computed `PlanStatus`. Credits percent = used / (used + balance).
    public static func percents(from status: PlanStatus) -> [AlertWindow: Double] {
        var out: [AlertWindow: Double] = [:]
        for w in status.windows {
            guard let p = w.percent else { continue }
            switch w.kind {
            case .fiveHour: out[.fiveHour] = p
            case .weekly:   out[.weekly] = p
            case .month:    break   // API budget has no threshold alerts (yet)
            }
        }
        if let c = status.credits, c.enabled,
           let used = c.usedThisPeriodMinorUnits {
            let total = used + (c.balanceMinorUnits ?? 0)
            if total > 0 { out[.credits] = Double(used) / Double(total) }
        }
        return out
    }
}
