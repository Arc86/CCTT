import Foundation

/// Minimal HTTP seam so the live provider is testable without real networking.
/// `URLSession` satisfies it as-is.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

/// The real `LiveLimitProvider`: borrows Claude Code's OAuth token, calls the
/// (unofficial) rate-limit endpoint, and classifies the result.
///
/// All live access is concentrated here (plus its decoder and Keychain source),
/// matching the spec's "one file to touch if the endpoint changes".
public struct NetworkLiveLimitProvider: LiveLimitProvider {
    /// Injected so retry backoff is instant in tests.
    public typealias Sleeper = @Sendable (TimeInterval) async -> Void

    private let credentials: CredentialsSource
    private let transport: HTTPTransport
    private let endpoint: URL
    private let clock: @Sendable () -> Date
    private let sleep: Sleeper

    /// Retries apply to `.transient` only.
    private static let maxRetries = 2
    private static let initialBackoff: TimeInterval = 1

    /// The rate-limit status endpoint Claude Code's `/status` consults. Unofficial
    /// and subject to change; overridable for testing and future migration.
    public static let defaultEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init(credentials: CredentialsSource = KeychainCredentialsSource(),
                transport: HTTPTransport = URLSession.shared,
                endpoint: URL = NetworkLiveLimitProvider.defaultEndpoint,
                clock: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping Sleeper = { try? await Task.sleep(for: .seconds($0)) }) {
        self.credentials = credentials
        self.transport = transport
        self.endpoint = endpoint
        self.clock = clock
        self.sleep = sleep
    }

    public func fetch() async -> LiveFetchResult {
        var backoff = Self.initialBackoff
        for tryIndex in 0...Self.maxRetries {
            let result = await attemptOnce()
            // Only a transient error is worth another go: a 429, a dead token, and
            // a changed schema all get worse (or stay broken) if hammered.
            guard case .transient = result.outcome, tryIndex < Self.maxRetries else {
                return result
            }
            await sleep(backoff)
            backoff *= 2
        }
        // Unreachable: the loop above always returns on its final iteration
        // (tryIndex == maxRetries fails the `tryIndex < Self.maxRetries` guard).
        // Present only to satisfy Swift's exhaustiveness checking.
        return LiveFetchResult(limits: nil, outcome: .transient)
    }

    /// One un-retried request, classified.
    private func attemptOnce() async -> LiveFetchResult {
        guard let creds = credentials.load(), !creds.isExpired(now: clock()) else {
            return LiveFetchResult(limits: nil, outcome: .unauthorized)
        }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await transport.data(for: request),
              let http = response as? HTTPURLResponse else {
            return LiveFetchResult(limits: nil, outcome: .transient)
        }

        switch http.statusCode {
        case 200...299:
            guard var live = LiveLimitsDecoder.decode(data) else {
                return LiveFetchResult(limits: nil, outcome: .malformed)
            }
            // Stamp when this reading came off the wire so the sticky cache and UI
            // can report its age if later polls fail.
            live.observedAt = clock()
            return LiveFetchResult(limits: live, outcome: .success)
        case 401, 403:
            return LiveFetchResult(limits: nil, outcome: .unauthorized)
        case 429:
            return LiveFetchResult(limits: nil,
                                   outcome: .rateLimited(retryAfter: retryAfter(from: http)))
        default:
            return LiveFetchResult(limits: nil, outcome: .transient)
        }
    }

    /// `Retry-After` as an absolute date. Only the delta-seconds form is parsed —
    /// the HTTP-date form is treated as absent, which just means we fall back to
    /// exponential backoff rather than an exact resume time.
    private func retryAfter(from response: HTTPURLResponse) -> Date? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return clock().addingTimeInterval(seconds)
    }
}
