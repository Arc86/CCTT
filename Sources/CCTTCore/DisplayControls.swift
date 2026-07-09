import Foundation

/// Unit the UI renders token figures in. Tokens are `.measured`; dollars are
/// `.derived` (shown with a "≈" affordance).
public enum DisplayUnit: Sendable, Equatable, CaseIterable {
    case tokens
    case dollars

    public var displayName: String {
        switch self {
        case .tokens:  return "Tokens"
        case .dollars: return "≈ $"
        }
    }
}

/// The detail window's global time-range control.
public enum TimeRange: Sendable, Equatable, CaseIterable {
    case fiveHour       // rolling last 5 hours
    case thisWeek       // current UTC calendar week, up to now
    case last7Days      // rolling last 7 days
    case last30Days     // rolling last 30 days
    case all            // all-time (no lower bound)

    public var displayName: String {
        switch self {
        case .fiveHour:   return "5h"
        case .thisWeek:   return "This week"
        case .last7Days:  return "7 days"
        case .last30Days: return "30 days"
        case .all:        return "All"
        }
    }

    /// The half-open-ish window `[start, now]` this range selects, or `nil` for
    /// all-time (no lower bound). Calendar math uses a fixed UTC gregorian
    /// calendar so results are machine-independent (matches Plan 2 windows).
    public func interval(now: Date) -> DateInterval? {
        switch self {
        case .fiveHour:
            return DateInterval(start: now.addingTimeInterval(-5 * 3600), end: now)
        case .last7Days:
            return DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        case .last30Days:
            return DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now)
        case .thisWeek:
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return DateInterval(start: start, end: now)
        case .all:
            return nil
        }
    }
}
