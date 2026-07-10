import Foundation
import Testing
@testable import CCTTCore

@Suite struct AppBundlingTests {
    @Test func recognizesDotAppBundle() {
        let url = URL(fileURLWithPath: "/Applications/CCTTApp.app")
        #expect(AppBundling.isBundled(url) == true)
    }

    @Test func bareBinaryIsNotBundled() {
        let url = URL(fileURLWithPath: "/Users/x/CCTT/.build/arm64-apple-macosx/debug/CCTTApp")
        #expect(AppBundling.isBundled(url) == false)
    }
}
