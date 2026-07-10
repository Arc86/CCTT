import Testing
@testable import CCTTCore

@Suite struct AppVersionTests {
    @Test func fallsBackToCoreVersionWhenUnbundled() {
        #expect(AppVersion.string(bundleShort: nil) == coreVersion)
    }

    @Test func prefersBundleShortVersionWhenPresent() {
        #expect(AppVersion.string(bundleShort: "1.4.0") == "1.4.0")
    }
}
