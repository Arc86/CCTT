import Foundation

/// Per-million-token USD pricing for one model family.
public struct ModelPrice: Sendable, Equatable {
    public var inputPerMTok: Double
    public var outputPerMTok: Double
    public var cacheWritePerMTok: Double   // cache creation (5-minute write): 1.25x input
    public var cacheReadPerMTok: Double    // cache read: 0.1x input

    public init(inputPerMTok: Double, outputPerMTok: Double,
                cacheWritePerMTok: Double, cacheReadPerMTok: Double) {
        self.inputPerMTok = inputPerMTok; self.outputPerMTok = outputPerMTok
        self.cacheWritePerMTok = cacheWritePerMTok; self.cacheReadPerMTok = cacheReadPerMTok
    }

    /// Derived dollar cost for a group of tokens ("≈ cost", `.derived` provenance).
    public func costUSD(for t: TokenTotals) -> Double {
        (Double(t.input) * inputPerMTok
         + Double(t.output) * outputPerMTok
         + Double(t.cacheCreation) * cacheWritePerMTok
         + Double(t.cacheRead) * cacheReadPerMTok) / 1_000_000
    }
}

/// Bundled, versioned price table keyed by lowercase model-family token.
/// Values are Anthropic public per-MTok pricing; cache-write = 1.25x input,
/// cache-read = 0.1x input.
public struct PriceTable: Sendable, Equatable {
    public let version: String
    public let prices: [String: ModelPrice]

    public init(version: String, prices: [String: ModelPrice]) {
        self.version = version; self.prices = prices
    }

    /// Resolve a full model id (e.g. "claude-opus-4-8[1m]") to its family price
    /// by case-insensitive substring match; `nil` when unrecognized.
    public func price(forModel model: String) -> ModelPrice? {
        let lower = model.lowercased()
        for (family, price) in prices where lower.contains(family) { return price }
        return nil
    }

    /// Sum derived cost across per-model rollups; unknown models contribute 0.
    public func costUSD(forByModel rollups: [Rollup]) -> Double {
        rollups.reduce(0) { $0 + (price(forModel: $1.key)?.costUSD(for: $1.totals) ?? 0) }
    }

    public static let bundled = PriceTable(
        version: "2026-07-08",
        prices: [
            "opus":   ModelPrice(inputPerMTok: 5,  outputPerMTok: 25, cacheWritePerMTok: 6.25,  cacheReadPerMTok: 0.50),
            "sonnet": ModelPrice(inputPerMTok: 3,  outputPerMTok: 15, cacheWritePerMTok: 3.75,  cacheReadPerMTok: 0.30),
            "haiku":  ModelPrice(inputPerMTok: 1,  outputPerMTok: 5,  cacheWritePerMTok: 1.25,  cacheReadPerMTok: 0.10),
            "fable":  ModelPrice(inputPerMTok: 10, outputPerMTok: 50, cacheWritePerMTok: 12.50, cacheReadPerMTok: 1.00),
        ]
    )
}
