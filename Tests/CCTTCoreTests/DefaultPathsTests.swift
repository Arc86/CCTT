import Testing
import Foundation
@testable import CCTTCore

@Test func projectsDirIsUnderHomeClaude() {
    #expect(DefaultPaths.projectsDir.path.hasSuffix(".claude/projects"))
}

@Test func offsetCacheIsUnderAppSupport() {
    let p = DefaultPaths.offsetCacheURL.path
    #expect(p.contains("Application Support/CCTT"))
    #expect(p.hasSuffix("offsets.json"))
}

@Test func formatsTokenMagnitudes() {
    #expect(DefaultPaths.formatTokens(123) == "123")
    #expect(DefaultPaths.formatTokens(12_345) == "12.3K")
    #expect(DefaultPaths.formatTokens(1_234_567) == "1.2M")
    #expect(DefaultPaths.formatTokens(0) == "0")
}
