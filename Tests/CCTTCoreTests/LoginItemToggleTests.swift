import Testing
@testable import CCTTCore

private final class StubLogin: LoginItemControlling {
    var enabled = false
    var throwOnSet = false
    struct Failure: Error {}
    var isEnabled: Bool { enabled }
    func setEnabled(_ e: Bool) throws {
        if throwOnSet { throw Failure() }
        enabled = e
    }
}

@Suite struct LoginItemToggleTests {
    @Test func applySucceedsAndReturnsDesired() {
        let stub = StubLogin()
        let toggle = LoginItemToggle(stub)
        #expect(toggle.apply(desired: true) == true)
        #expect(stub.enabled == true)
    }

    @Test func applyRevertsToActualStateOnError() {
        let stub = StubLogin()
        stub.enabled = false
        stub.throwOnSet = true
        let toggle = LoginItemToggle(stub)
        #expect(toggle.apply(desired: true) == false)   // reverted, not desired
        #expect(stub.enabled == false)
    }
}
