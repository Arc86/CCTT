import Foundation
import Testing
@testable import CCTTCore

/// Returns scripted values in order and counts how many times it was consulted,
/// so we can prove the cache avoids hitting the wrapped (Keychain) source.
private final class CountingCredentialsSource: CredentialsSource, @unchecked Sendable {
    private(set) var callCount = 0
    private var scripted: [ClaudeCredentials?]

    init(_ scripted: [ClaudeCredentials?]) { self.scripted = scripted }

    func load() -> ClaudeCredentials? {
        defer { callCount += 1 }
        if scripted.count > 1 { return scripted.removeFirst() }
        return scripted.first ?? nil
    }
}

private final class MutableClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

struct CachingCredentialsSourceTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)
    private func creds(_ token: String, expiresAt: Date?) -> ClaudeCredentials {
        ClaudeCredentials(accessToken: token, refreshToken: nil,
                          expiresAt: expiresAt, subscriptionType: "max")
    }

    @Test func reusesCachedTokenWithinValidityWithoutHittingWrapped() {
        let c1 = creds("tok-1", expiresAt: base.addingTimeInterval(3600))
        let spy = CountingCredentialsSource([c1])
        let cache = CachingCredentialsSource(wrapping: spy, clock: { self.base }, refreshMargin: 60)

        #expect(cache.load() == c1)
        #expect(cache.load() == c1)
        #expect(spy.callCount == 1)   // second read served from cache — no Keychain prompt
    }

    @Test func reReadsAfterTheCachedTokenExpires() {
        let c1 = creds("tok-1", expiresAt: base.addingTimeInterval(3600))
        let c2 = creds("tok-2", expiresAt: base.addingTimeInterval(7200))
        let spy = CountingCredentialsSource([c1, c2])
        let clock = MutableClock(base)
        let cache = CachingCredentialsSource(wrapping: spy, clock: { clock.now }, refreshMargin: 60)

        #expect(cache.load() == c1)
        clock.now = base.addingTimeInterval(3601)   // past expiry
        #expect(cache.load() == c2)
        #expect(spy.callCount == 2)
    }

    @Test func refreshMarginReReadsShortlyBeforeExpiry() {
        let c1 = creds("tok-1", expiresAt: base.addingTimeInterval(3600))
        let c2 = creds("tok-2", expiresAt: base.addingTimeInterval(7200))
        let spy = CountingCredentialsSource([c1, c2])
        let clock = MutableClock(base)
        let cache = CachingCredentialsSource(wrapping: spy, clock: { clock.now }, refreshMargin: 60)

        #expect(cache.load() == c1)
        clock.now = base.addingTimeInterval(3600 - 30)   // within the 60s margin
        #expect(cache.load() == c2)
        #expect(spy.callCount == 2)
    }

    @Test func doesNotCacheAFailedRead() {
        let c1 = creds("tok-1", expiresAt: base.addingTimeInterval(3600))
        let spy = CountingCredentialsSource([nil, c1])
        let cache = CachingCredentialsSource(wrapping: spy, clock: { self.base }, refreshMargin: 60)

        #expect(cache.load() == nil)   // wrapped miss is not cached…
        #expect(cache.load() == c1)    // …so a later success still gets through
        #expect(spy.callCount == 2)
    }

    @Test func nonExpiringTokenIsCachedForProcessLifetime() {
        let c1 = creds("tok-1", expiresAt: nil)
        let c2 = creds("tok-2", expiresAt: nil)
        let spy = CountingCredentialsSource([c1, c2])
        let clock = MutableClock(base)
        let cache = CachingCredentialsSource(wrapping: spy, clock: { clock.now }, refreshMargin: 60)

        #expect(cache.load() == c1)
        clock.now = base.addingTimeInterval(10 * 3600)   // long later
        #expect(cache.load() == c1)                      // still cached; no re-read
        #expect(spy.callCount == 1)
    }
}
