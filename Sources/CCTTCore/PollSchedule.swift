import Foundation

/// How long to wait before the next live-limit poll, given how the last one went.
///
/// We previously polled a fixed 120s regardless of being throttled — which is part
/// of *why* the endpoint 429s at us. This backs off on failure and snaps back to
/// the base interval the moment a poll succeeds.
public struct PollSchedule: Sendable, Equatable {
    /// The healthy poll interval: current enough to be useful, sparse enough to
    /// stay inside the endpoint's budget.
    public static let base: TimeInterval = 120
    /// Never wait longer than this, so recovery is always bounded.
    public static let cap: TimeInterval = 30 * 60

    public let interval: TimeInterval

    public init(interval: TimeInterval = PollSchedule.base) {
        self.interval = interval
    }

    public func next(after outcome: LiveFetchOutcome, now: Date) -> PollSchedule {
        switch outcome {
        case .success, .disabled:
            return PollSchedule(interval: Self.base)

        case .rateLimited(let retryAfter):
            let backedOff = min(interval * 2, Self.cap)
            guard let retryAfter else { return PollSchedule(interval: backedOff) }
            // Honour the server's wait when it is longer than ours; never poll
            // sooner than our own backoff just because it said we could.
            let requested = retryAfter.timeIntervalSince(now)
            return PollSchedule(interval: min(max(requested, backedOff), Self.cap))

        case .unauthorized, .transient, .malformed:
            // `.unauthorized` backs off rather than stopping: Claude Code refreshes
            // the OAuth token on its own, so a 401 can resolve with no user action.
            return PollSchedule(interval: min(interval * 2, Self.cap))
        }
    }
}
