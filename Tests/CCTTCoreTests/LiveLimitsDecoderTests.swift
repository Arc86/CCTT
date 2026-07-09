import Foundation
import Testing
@testable import CCTTCore

/// The decoder is the single point that understands the (unofficial) rate-limit
/// endpoint's JSON shape. These tests pin the contract it decodes; if the real
/// API differs, only the decoder and these tests change (spec §6 "one file").
struct LiveLimitsDecoderTests {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func decodesFullResponse() throws {
        let json = """
        {
          "five_hour":  { "utilization": 0.42, "resets_at": "2026-07-09T15:00:00Z" },
          "seven_day":  { "utilization": 0.13, "resets_at": "2026-07-14T00:00:00Z" },
          "credits":    { "balance_minor_units": 4200, "used_minor_units": 800, "currency": "EUR" }
        }
        """
        let live = try #require(LiveLimitsDecoder.decode(data(json)))
        #expect(live.fiveHourPercent == 0.42)
        #expect(live.weeklyPercent == 0.13)
        #expect(live.creditBalanceMinorUnits == 4200)
        #expect(live.creditUsedMinorUnits == 800)
        #expect(live.currency == "EUR")

        let iso = ISO8601DateFormatter()
        #expect(live.fiveHourResetsAt == iso.date(from: "2026-07-09T15:00:00Z"))
        #expect(live.weeklyResetsAt == iso.date(from: "2026-07-14T00:00:00Z"))
    }

    @Test func decodesPartialResponse() throws {
        let json = """
        { "five_hour": { "utilization": 0.9 } }
        """
        let live = try #require(LiveLimitsDecoder.decode(data(json)))
        #expect(live.fiveHourPercent == 0.9)
        #expect(live.weeklyPercent == nil)
        #expect(live.fiveHourResetsAt == nil)
        #expect(live.creditBalanceMinorUnits == nil)
    }

    @Test func returnsNilForMalformedJSON() {
        #expect(LiveLimitsDecoder.decode(data("{not json")) == nil)
        #expect(LiveLimitsDecoder.decode(Data()) == nil)
    }

    @Test func returnsNilWhenNoKnownFieldsPresent() {
        #expect(LiveLimitsDecoder.decode(data(#"{ "unrelated": 1 }"#)) == nil)
    }

    /// Tolerant to a percentage expressed 0–100 instead of a 0–1 fraction:
    /// values > 1 are normalised by /100 so the engine always sees a fraction.
    @Test func normalizesPercentGivenAsWholeNumber() throws {
        let json = #"{ "seven_day": { "utilization": 55 } }"#
        let live = try #require(LiveLimitsDecoder.decode(data(json)))
        #expect(live.weeklyPercent == 0.55)
    }
}
