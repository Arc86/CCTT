/// Summed token counts for a group of usage events.
public struct TokenTotals: Sendable, Equatable, Codable {
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int
    public var webSearch: Int
    public var webFetch: Int
    public var eventCount: Int

    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0,
                cacheRead: Int = 0, webSearch: Int = 0, webFetch: Int = 0,
                eventCount: Int = 0) {
        self.input = input; self.output = output
        self.cacheCreation = cacheCreation; self.cacheRead = cacheRead
        self.webSearch = webSearch; self.webFetch = webFetch
        self.eventCount = eventCount
    }

    public static let zero = TokenTotals()

    /// All token categories summed. Note: cache-read is billed cheaper than
    /// fresh input; this is a raw token sum, not a cost. Pricing lands in Plan 2.
    public var total: Int { input + output + cacheCreation + cacheRead }

    public static func + (lhs: TokenTotals, rhs: TokenTotals) -> TokenTotals {
        TokenTotals(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheCreation: lhs.cacheCreation + rhs.cacheCreation,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            webSearch: lhs.webSearch + rhs.webSearch,
            webFetch: lhs.webFetch + rhs.webFetch,
            eventCount: lhs.eventCount + rhs.eventCount
        )
    }

    public static func += (lhs: inout TokenTotals, rhs: TokenTotals) {
        lhs = lhs + rhs
    }
}
