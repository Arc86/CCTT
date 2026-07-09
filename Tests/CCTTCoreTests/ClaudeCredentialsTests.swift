import Foundation
import Testing
@testable import CCTTCore

/// Claude Code stores its OAuth token in the macOS Keychain as a JSON blob under
/// the `claudeAiOauth` key. The decoder turns that blob into `ClaudeCredentials`;
/// the Keychain read itself sits behind the `CredentialsSource` seam.
struct ClaudeCredentialsTests {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    @Test func decodesKeychainBlob() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-ant-oat01-abc",
            "refreshToken": "sk-ant-ort01-xyz",
            "expiresAt": 1751990400000,
            "subscriptionType": "max"
          }
        }
        """
        let creds = try #require(ClaudeCredentialsDecoder.decode(data(json)))
        #expect(creds.accessToken == "sk-ant-oat01-abc")
        #expect(creds.refreshToken == "sk-ant-ort01-xyz")
        #expect(creds.subscriptionType == "max")
        // expiresAt is epoch milliseconds.
        #expect(creds.expiresAt == Date(timeIntervalSince1970: 1_751_990_400))
    }

    @Test func decodesWithoutOptionalFields() throws {
        let json = #"{ "claudeAiOauth": { "accessToken": "tok" } }"#
        let creds = try #require(ClaudeCredentialsDecoder.decode(data(json)))
        #expect(creds.accessToken == "tok")
        #expect(creds.refreshToken == nil)
        #expect(creds.expiresAt == nil)
    }

    @Test func returnsNilWithoutAccessToken() {
        #expect(ClaudeCredentialsDecoder.decode(data(#"{ "claudeAiOauth": {} }"#)) == nil)
        #expect(ClaudeCredentialsDecoder.decode(data("{not json")) == nil)
        #expect(ClaudeCredentialsDecoder.decode(Data()) == nil)
    }

    @Test func expiryIsRelativeToInjectedClock() {
        let creds = ClaudeCredentials(accessToken: "t", refreshToken: nil,
                                      expiresAt: Date(timeIntervalSince1970: 1000),
                                      subscriptionType: nil)
        #expect(creds.isExpired(now: Date(timeIntervalSince1970: 1001)))
        #expect(!creds.isExpired(now: Date(timeIntervalSince1970: 999)))
    }

    @Test func credentialsWithoutExpiryNeverExpire() {
        let creds = ClaudeCredentials(accessToken: "t", refreshToken: nil,
                                      expiresAt: nil, subscriptionType: nil)
        #expect(!creds.isExpired(now: Date(timeIntervalSince1970: 9_999_999_999)))
    }

    @Test func staticSourceReturnsInjectedCredentials() {
        let creds = ClaudeCredentials(accessToken: "t", refreshToken: nil,
                                      expiresAt: nil, subscriptionType: nil)
        #expect(StaticCredentialsSource(creds).load()?.accessToken == "t")
        #expect(StaticCredentialsSource(nil).load() == nil)
    }
}
