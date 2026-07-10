import Foundation

/// Minimal HTTP seam so the live provider is testable without real networking.
/// `URLSession` satisfies it as-is.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

/// The real `LiveLimitProvider`: borrows Claude Code's OAuth token, calls the
/// (unofficial) rate-limit endpoint, and decodes the response. Any failure —
/// missing/expired token, network error, non-200, unrecognised body — returns
/// `nil`, so the engine transparently falls back to the estimate path.
///
/// All live access is concentrated here (plus its decoder and Keychain source),
/// matching the spec's "one file to touch if the endpoint changes".
public struct NetworkLiveLimitProvider: LiveLimitProvider {
    private let credentials: CredentialsSource
    private let transport: HTTPTransport
    private let endpoint: URL
    private let clock: @Sendable () -> Date

    /// The rate-limit status endpoint Claude Code's `/status` consults. Unofficial
    /// and subject to change; overridable for testing and future migration.
    public static let defaultEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init(credentials: CredentialsSource = KeychainCredentialsSource(),
                transport: HTTPTransport = URLSession.shared,
                endpoint: URL = NetworkLiveLimitProvider.defaultEndpoint,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.credentials = credentials
        self.transport = transport
        self.endpoint = endpoint
        self.clock = clock
    }

    public func fetch() async -> LiveLimits? {
        guard let creds = credentials.load(), !creds.isExpired(now: clock()) else { return nil }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await transport.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { return nil }

        // Stamp when this reading came off the wire so the sticky cache and UI
        // can report its age if later polls fail (e.g. the endpoint 429s).
        guard var live = LiveLimitsDecoder.decode(data) else { return nil }
        live.observedAt = clock()
        return live
    }
}
