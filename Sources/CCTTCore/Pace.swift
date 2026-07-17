import Foundation

/// How the current burn rate compares to what the window can sustain.
public enum PaceStatus: Sendable, Equatable {
    /// Projected to finish the window under the cap.
    case onTrack
    /// Projected to land on or just past the cap.
    case atRisk
    /// Projected to blow through the cap with time to spare.
    case willExceed
}

/// A window's burn rate: how fast you are consuming it, and when you run out.
///
/// Answers the question a token tracker exists for — "am I going to run out?" —
/// rather than only "how much have I used?". Adapted from ClaudeMeter's
/// `UsageLimit.isAtRisk(windowDuration:)`, but re-anchored: theirs compares a rate
/// ratio, ours compares *projected end-of-window consumption*, which is directly
/// interpretable ("1.4 = you'd hit 140% of the cap by reset").
public struct Pace: Sendable, Equatable {
    /// Fraction of the cap projected to be consumed by the window's end at the
    /// current rate. 1.0 means landing exactly on the cap.
    public let ratio: Double
    public let status: PaceStatus
    /// When the cap is projected to be hit, or `nil` when that never happens
    /// before the window resets. Equal to `now` when already at or over the cap.
    public let exhaustsAt: Date?
    /// Inherited from the percentage this was computed from — never invented.
    /// A pace derived from an estimated percent is itself `.estimated`.
    public let provenance: Provenance

    public init(ratio: Double, status: PaceStatus, exhaustsAt: Date?, provenance: Provenance) {
        self.ratio = ratio; self.status = status
        self.exhaustsAt = exhaustsAt; self.provenance = provenance
    }
}

public extension Pace {
    /// Projected consumption at or above this is `.willExceed`. ClaudeMeter's
    /// `Constants.Pacing.riskThreshold`, re-anchored onto projected consumption.
    static let riskThreshold: Double = 1.2

    /// Evaluate the pace of a window ending at `windowEnd` and lasting `duration`.
    ///
    /// `windowStart` is derived as `windowEnd - duration`, so one signature serves
    /// both paths: live supplies `reset_at`, estimated supplies the session block's
    /// `end`. Returns `nil` when pacing is undefined — no usage yet, `now` outside
    /// the window, or a non-positive duration.
    static func evaluate(percent: Double, windowEnd: Date, duration: TimeInterval,
                         now: Date, provenance: Provenance) -> Pace? {
        guard duration > 0, percent > 0 else { return nil }
        let windowStart = windowEnd.addingTimeInterval(-duration)
        guard now > windowStart, now < windowEnd else { return nil }

        let elapsed = now.timeIntervalSince(windowStart)
        let ratio = percent / (elapsed / duration)
        let status: PaceStatus = ratio >= riskThreshold ? .willExceed
                               : (ratio >= 1.0 ? .atRisk : .onTrack)

        // Time to reach 100% at the current rate. Clamped at 0 so an already-over
        // window reports "exhausted now" rather than a date in the past.
        let secondsToFull = max(0, (1.0 - percent) * elapsed / percent)
        let projected = now.addingTimeInterval(secondsToFull)
        let exhaustsAt: Date? = projected < windowEnd ? projected : nil

        return Pace(ratio: ratio, status: status, exhaustsAt: exhaustsAt,
                    provenance: provenance)
    }
}
