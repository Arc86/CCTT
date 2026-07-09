import Foundation

/// Claude Code's OAuth credentials, read (read-only) from the macOS Keychain.
/// CCTT never writes these; it borrows the existing token to call the same
/// rate-limit endpoint Claude Code uses.
public struct ClaudeCredentials: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let subscriptionType: String?

    public init(accessToken: String, refreshToken: String?,
                expiresAt: Date?, subscriptionType: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
    }

    /// True once the injected clock passes `expiresAt`. Credentials with no
    /// known expiry are treated as non-expiring (the caller degrades on a 401).
    public func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}

/// Decodes the Keychain JSON blob Claude Code stores under `claudeAiOauth`.
/// Tolerant: any decode failure or a missing access token yields `nil`.
public enum ClaudeCredentialsDecoder {

    public static func decode(_ data: Data) -> ClaudeCredentials? {
        guard !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }

        let expiresAt = (oauth["expiresAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }  // epoch ms → s

        return ClaudeCredentials(
            accessToken: token,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }
}

/// Seam for reading the OAuth token. The whole live path depends only on this
/// protocol, so tests inject `StaticCredentialsSource` and never touch Keychain.
public protocol CredentialsSource: Sendable {
    func load() -> ClaudeCredentials?
}

/// Test / dev source returning a fixed value.
public struct StaticCredentialsSource: CredentialsSource {
    private let value: ClaudeCredentials?
    public init(_ value: ClaudeCredentials?) { self.value = value }
    public func load() -> ClaudeCredentials? { value }
}
