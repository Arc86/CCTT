import Testing
import Foundation
@testable import CCTTCore

@Test func totalContextIsSumOfInputAndCaches() {
    let e = UsageEvent.fixture(input: 1000, cacheCreation: 200, cacheRead: 500)
    #expect(e.totalContextTokens == 1700)
}

@Test func agentKindReflectsSidechain() {
    #expect(UsageEvent.fixture(isSidechain: false).agentKind == "main")
    #expect(UsageEvent.fixture(isSidechain: true).agentKind == "subagent")
}

@Test func dedupKeyRequiresBothIds() {
    #expect(UsageEvent.fixture(requestId: "r1", messageId: "m1").dedupKey == "r1|m1")
    #expect(UsageEvent.fixture(requestId: nil, messageId: "m1").dedupKey == nil)
}

@Test func tokenTotalsAddition() {
    let a = TokenTotals(input: 1, output: 2, cacheCreation: 3, cacheRead: 4,
                        webSearch: 0, webFetch: 0, eventCount: 1)
    let b = TokenTotals(input: 10, output: 20, cacheCreation: 30, cacheRead: 40,
                        webSearch: 1, webFetch: 2, eventCount: 1)
    let sum = a + b
    #expect(sum.input == 11)
    #expect(sum.total == 11 + 22 + 33 + 44)
    #expect(sum.eventCount == 2)
    #expect(sum.webFetch == 2)
}
