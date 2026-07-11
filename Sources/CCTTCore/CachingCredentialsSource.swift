import Foundation

/// Wraps another `CredentialsSource` and keeps the last successful read in memory,
/// so the underlying Keychain is only consulted when there is no valid cached
/// token — not on every 120s live-limit poll.
///
/// Why this exists: reading Claude Code's Keychain item is what triggers the
/// system access prompt. Reading it on every poll re-prompts the user unless they
/// picked "Always Allow", and even then keeps the app on the item's ACL hot path.
/// Caching until the token nears expiry (`refreshMargin`) collapses those repeated
/// reads to roughly one per token lifetime. A failed read is never cached, so the
/// app can still recover the moment credentials become available.
public final class CachingCredentialsSource: CredentialsSource, @unchecked Sendable {
    private let wrapped: CredentialsSource
    private let clock: @Sendable () -> Date
    private let refreshMargin: TimeInterval
    private let lock = NSLock()
    private var cached: ClaudeCredentials?

    /// - Parameters:
    ///   - wrapped: the real source (e.g. `KeychainCredentialsSource`).
    ///   - clock: injected time, so expiry is deterministic in tests.
    ///   - refreshMargin: re-read this many seconds *before* the cached token's
    ///     expiry, so a fetch never goes out with a just-expired token.
    public init(wrapping wrapped: CredentialsSource,
                clock: @escaping @Sendable () -> Date = { Date() },
                refreshMargin: TimeInterval = 60) {
        self.wrapped = wrapped
        self.clock = clock
        self.refreshMargin = refreshMargin
    }

    public func load() -> ClaudeCredentials? {
        // Held across the wrapped read so concurrent polls can't each fire a
        // separate Keychain prompt — the second caller sees the fresh cache.
        lock.lock()
        defer { lock.unlock() }

        if let cached, !cached.isExpired(now: clock().addingTimeInterval(refreshMargin)) {
            return cached
        }
        let fresh = wrapped.load()
        if let fresh { cached = fresh }
        return fresh
    }
}
