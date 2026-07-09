import Foundation
import Security

/// Reads Claude Code's OAuth credentials from the login Keychain. Claude Code
/// stores them as a generic-password item whose service is
/// `"Claude Code-credentials"`; the item's data is the JSON blob decoded by
/// `ClaudeCredentialsDecoder`. Read-only — CCTT never writes the item.
///
/// The first read triggers the system Keychain-access prompt; declining leaves
/// the app on the estimate path (`load()` returns `nil`).
public struct KeychainCredentialsSource: CredentialsSource {
    private let service: String

    public init(service: String = "Claude Code-credentials") {
        self.service = service
    }

    public func load() -> ClaudeCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return ClaudeCredentialsDecoder.decode(data)
    }
}
