import Foundation
import Testing
@testable import CCTTCore

/// Records the last request and returns a canned response, so the provider's
/// composition (auth header, decoding, classification, retry) is testable offline.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    let body: Data
    let statusCode: Int
    let headers: [String: String]
    let error: Error?
    private(set) var lastRequest: URLRequest?
    private(set) var callCount = 0

    init(body: Data = Data(), statusCode: Int = 200, headers: [String: String] = [:],
         error: Error? = nil) {
        self.body = body; self.statusCode = statusCode; self.headers = headers; self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        lastRequest = request
        if let error { throw error }
        let resp = HTTPURLResponse(url: request.url!, statusCode: statusCode,
                                   httpVersion: nil, headerFields: headers)!
        return (body, resp)
    }
}

struct NetworkLiveLimitProviderTests {

    private let endpoint = URL(string: "https://example.invalid/limits")!
    private func creds(expiresAt: Date? = nil) -> ClaudeCredentials {
        ClaudeCredentials(accessToken: "tok-123", refreshToken: nil,
                          expiresAt: expiresAt, subscriptionType: "max")
    }

    @Test func fetchesDecodesAndAuthorizes() async throws {
        let json = Data(#"{ "five_hour": { "utilization": 50 } }"#.utf8)  // 0–100 scale
        let transport = StubTransport(body: json, statusCode: 200)
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()), transport: transport,
            endpoint: endpoint, clock: { Date(timeIntervalSince1970: 0) }, sleep: { _ in })

        let out = await provider.fetch()
        #expect(out.limits?.fiveHourPercent == 0.5)
        #expect(out.outcome == .success)
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-123")
    }

    @Test func stampsObservedAtOnSuccess() async {
        let json = Data(#"{ "five_hour": { "utilization": 0.5 } }"#.utf8)
        let clock = Date(timeIntervalSince1970: 1_783_000_123)
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()),
            transport: StubTransport(body: json, statusCode: 200),
            endpoint: endpoint, clock: { clock }, sleep: { _ in })
        // The stamp lets a later failing poll report the reading's age.
        #expect(await provider.fetch().limits?.observedAt == clock)
    }

    @Test func returnsUnauthorizedWithoutCredentials() async {
        let transport = StubTransport()
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(nil), transport: transport,
            endpoint: endpoint, clock: { Date(timeIntervalSince1970: 0) }, sleep: { _ in })
        let out = await provider.fetch()
        #expect(out.limits == nil)
        #expect(out.outcome == .unauthorized)
        #expect(transport.callCount == 0)   // never hits the network
    }

    @Test func returnsUnauthorizedForExpiredCredentialsWithoutCallingNetwork() async {
        let transport = StubTransport(body: Data(#"{"five_hour":{"utilization":0.5}}"#.utf8))
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds(expiresAt: Date(timeIntervalSince1970: 100))),
            transport: transport, endpoint: endpoint,
            clock: { Date(timeIntervalSince1970: 200) }, sleep: { _ in })   // past expiry
        let out = await provider.fetch()
        #expect(out.limits == nil)
        #expect(out.outcome == .unauthorized)
        #expect(transport.callCount == 0)
    }

    @Test func degradesToTransientOnTransportError() async {
        struct Boom: Error {}
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()),
            transport: StubTransport(error: Boom()), endpoint: endpoint,
            clock: { Date(timeIntervalSince1970: 0) }, sleep: { _ in })
        let out = await provider.fetch()
        #expect(out.limits == nil)
        #expect(out.outcome == .transient)
    }

    // MARK: - Outcome classification

    @Test func rateLimitedParsesRetryAfterSeconds() async {
        let now = Date(timeIntervalSince1970: 1_784_278_800)
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()),
            transport: StubTransport(statusCode: 429, headers: ["Retry-After": "600"]),
            endpoint: endpoint, clock: { now }, sleep: { _ in })
        let out = await provider.fetch()
        #expect(out.outcome == .rateLimited(retryAfter: now.addingTimeInterval(600)))
        #expect(out.limits == nil)
    }

    @Test func rateLimitedWithoutAParseableRetryAfterYieldsNilDate() async {
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()),
            transport: StubTransport(statusCode: 429),
            endpoint: endpoint, clock: { Date(timeIntervalSince1970: 1_784_278_800) },
            sleep: { _ in })
        #expect(await provider.fetch().outcome == .rateLimited(retryAfter: nil))
    }

    @Test func unauthorizedOn401() async {
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()),
            transport: StubTransport(statusCode: 401),
            endpoint: endpoint, clock: { Date(timeIntervalSince1970: 1_784_278_800) },
            sleep: { _ in })
        #expect(await provider.fetch().outcome == .unauthorized)
    }

    @Test func malformedOnUndecodableTwoHundred() async {
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()),
            transport: StubTransport(body: Data("not json".utf8), statusCode: 200),
            endpoint: endpoint, clock: { Date(timeIntervalSince1970: 1_784_278_800) },
            sleep: { _ in })
        #expect(await provider.fetch().outcome == .malformed)
    }

    @Test func transientIsRetriedTwiceThenGivesUp() async {
        let transport = StubTransport(statusCode: 500)
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()),
            transport: transport,
            endpoint: endpoint, clock: { Date(timeIntervalSince1970: 1_784_278_800) },
            sleep: { _ in })
        #expect(await provider.fetch().outcome == .transient)
        #expect(transport.callCount == 3)   // initial + 2 retries
    }

    @Test func rateLimitIsNeverRetried() async {
        // Retrying a 429 is pure harm — it is why the endpoint throttles us.
        let transport = StubTransport(statusCode: 429)
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()),
            transport: transport,
            endpoint: endpoint, clock: { Date(timeIntervalSince1970: 1_784_278_800) },
            sleep: { _ in })
        _ = await provider.fetch()
        #expect(transport.callCount == 1)
    }
}
