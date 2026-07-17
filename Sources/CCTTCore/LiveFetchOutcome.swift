import Foundation

/// Why a live rate-limit fetch ended the way it did.
///
/// Replaces the old `LiveLimits?` return, which collapsed a dead token, a 429, a
/// network blip, and a changed response schema into one indistinguishable `nil` —
/// leaving the app unable to back off intelligently or tell the user to reconnect.
public enum LiveFetchOutcome: Sendable, Equatable {
    /// A fresh reading came off the wire.
    case success
    /// The endpoint rate-limited us. `retryAfter` is parsed from the `Retry-After`
    /// header when present and parseable; `nil` otherwise.
    case rateLimited(retryAfter: Date?)
    /// The token is missing, expired, or rejected. Actionable by the user.
    case unauthorized
    /// A network error or an unexpected 5xx — worth retrying.
    case transient
    /// A 2xx the decoder could not understand: the endpoint likely changed shape.
    /// Never retried — retrying a schema change is pure harm.
    case malformed
    /// Live limits are switched off. Not an error.
    case disabled
}

/// A live fetch's value and its reason, together.
///
/// The two channels are independent: `StickyLiveLimitProvider` serves a stale-but-real
/// `limits` alongside a failure `outcome`, so the UI can render the real number *and*
/// label its health honestly.
public struct LiveFetchResult: Sendable, Equatable {
    /// The reading to use. May be a stale last-good value when `outcome` is a failure.
    public let limits: LiveLimits?
    public let outcome: LiveFetchOutcome

    public init(limits: LiveLimits?, outcome: LiveFetchOutcome) {
        self.limits = limits; self.outcome = outcome
    }

    public static let disabled = LiveFetchResult(limits: nil, outcome: .disabled)
}
