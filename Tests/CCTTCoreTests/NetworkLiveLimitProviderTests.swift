import Foundation
import Testing
@testable import CCTTCore

/// Records the last request and returns a canned response, so the provider's
/// composition (auth header, decoding, degradation) is testable offline.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    let body: Data
    let statusCode: Int
    let error: Error?
    private(set) var lastRequest: URLRequest?
    private(set) var callCount = 0

    init(body: Data = Data(), statusCode: Int = 200, error: Error? = nil) {
        self.body = body; self.statusCode = statusCode; self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        lastRequest = request
        if let error { throw error }
        let resp = HTTPURLResponse(url: request.url!, statusCode: statusCode,
                                   httpVersion: nil, headerFields: nil)!
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
            endpoint: endpoint, clock: { Date(timeIntervalSince1970: 0) })

        let live = await provider.fetch()
        #expect(live?.fiveHourPercent == 0.5)
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-123")
    }

    @Test func stampsObservedAtOnSuccess() async {
        let json = Data(#"{ "five_hour": { "utilization": 0.5 } }"#.utf8)
        let clock = Date(timeIntervalSince1970: 1_783_000_123)
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()),
            transport: StubTransport(body: json, statusCode: 200),
            endpoint: endpoint, clock: { clock })
        // The stamp lets a later failing poll report the reading's age.
        #expect(await provider.fetch()?.observedAt == clock)
    }

    @Test func returnsNilWithoutCredentials() async {
        let transport = StubTransport()
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(nil), transport: transport,
            endpoint: endpoint, clock: { Date(timeIntervalSince1970: 0) })
        #expect(await provider.fetch() == nil)
        #expect(transport.callCount == 0)   // never hits the network
    }

    @Test func returnsNilForExpiredCredentialsWithoutCallingNetwork() async {
        let transport = StubTransport(body: Data(#"{"five_hour":{"utilization":0.5}}"#.utf8))
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds(expiresAt: Date(timeIntervalSince1970: 100))),
            transport: transport, endpoint: endpoint,
            clock: { Date(timeIntervalSince1970: 200) })   // past expiry
        #expect(await provider.fetch() == nil)
        #expect(transport.callCount == 0)
    }

    @Test func degradesToNilOnTransportError() async {
        struct Boom: Error {}
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()),
            transport: StubTransport(error: Boom()), endpoint: endpoint,
            clock: { Date(timeIntervalSince1970: 0) })
        #expect(await provider.fetch() == nil)
    }

    @Test func degradesToNilOnNon200() async {
        let transport = StubTransport(body: Data(#"{"five_hour":{"utilization":0.5}}"#.utf8),
                                      statusCode: 401)
        let provider = NetworkLiveLimitProvider(
            credentials: StaticCredentialsSource(creds()), transport: transport,
            endpoint: endpoint, clock: { Date(timeIntervalSince1970: 0) })
        #expect(await provider.fetch() == nil)
    }
}
