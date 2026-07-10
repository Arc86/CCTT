import Testing
@testable import CCTTCore

@Suite struct DisabledUpdaterTests {
    @Test func cannotCheckAndDoesNotCrash() {
        let u = DisabledUpdater()
        #expect(u.canCheckForUpdates == false)
        u.automaticallyChecksForUpdates = true
        u.checkForUpdates()   // no-op, must not crash
        #expect(u.automaticallyChecksForUpdates == true)
    }
}
