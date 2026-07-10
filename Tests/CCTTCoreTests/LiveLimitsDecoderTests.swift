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
          "five_hour":  { "utilization": 42, "resets_at": "2026-07-09T15:00:00Z" },
          "seven_day":  { "utilization": 13, "resets_at": "2026-07-14T00:00:00Z" },
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
        { "five_hour": { "utilization": 90 } }
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

    /// `utilization` is a 0–100 percentage, so sub-1% usage (a value ≤ 1) must
    /// still divide by 100 — a real `seven_day: 1.0` is 1%, not 100%. This is the
    /// case the old `v > 1 ? v/100 : v` heuristic got wrong.
    @Test func normalizesUtilizationAsPercentageOutOf100() throws {
        let live = try #require(LiveLimitsDecoder.decode(data(#"{ "seven_day": { "utilization": 55 } }"#)))
        #expect(live.weeklyPercent == 0.55)

        let low = try #require(LiveLimitsDecoder.decode(data(#"{ "seven_day": { "utilization": 1.0 } }"#)))
        #expect(low.weeklyPercent == 0.01)
    }

    /// Pins the real endpoint payload captured from `/api/oauth/usage` so the
    /// decoder stays matched to the live shape (0–100 utilization, fractional-
    /// second offset timestamps, `extra_usage` credit block).
    @Test func decodesRealCapturedPayload() throws {
        let json = """
        {"five_hour":{"utilization":7.0,"resets_at":"2026-07-09T22:50:00.895576+00:00"},
         "seven_day":{"utilization":1.0,"resets_at":"2026-07-15T18:00:00.895599+00:00"},
         "extra_usage":{"is_enabled":false}}
        """
        let live = try #require(LiveLimitsDecoder.decode(data(json)))
        #expect(live.fiveHourPercent == 0.07)
        #expect(live.weeklyPercent == 0.01)
        #expect(live.fiveHourResetsAt != nil)
        #expect(live.weeklyResetsAt != nil)
        // extra_usage disabled → no live credit figures (no misleading $0).
        #expect(live.creditBalanceMinorUnits == nil)
        #expect(live.creditUsedMinorUnits == nil)
    }

    /// Live credits arrive under `extra_usage` as major-unit amounts; we scale to
    /// minor units (cents) and derive the remaining balance from the cap.
    @Test func decodesEnabledExtraUsageCredits() throws {
        let json = """
        {
          "five_hour": { "utilization": 8 },
          "extra_usage": { "is_enabled": true, "monthly_limit": 50.0,
                           "used_credits": 5.5, "decimal_places": 2, "currency": "USD" }
        }
        """
        let live = try #require(LiveLimitsDecoder.decode(data(json)))
        #expect(live.creditUsedMinorUnits == 550)        // $5.50 → 550¢
        #expect(live.creditBalanceMinorUnits == 4450)    // $50 − $5.50 = $44.50 → 4450¢
        #expect(live.currency == "USD")
    }

    /// A disabled extra-usage block yields no credit figures even when present.
    @Test func ignoresDisabledExtraUsage() throws {
        let json = #"{ "five_hour": { "utilization": 8 }, "extra_usage": { "is_enabled": false, "used_credits": null } }"#
        let live = try #require(LiveLimitsDecoder.decode(data(json)))
        #expect(live.creditBalanceMinorUnits == nil)
        #expect(live.creditUsedMinorUnits == nil)
    }
}
