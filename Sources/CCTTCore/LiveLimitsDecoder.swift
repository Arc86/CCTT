import Foundation

/// Decodes the (unofficial) Claude Code rate-limit endpoint response into
/// `LiveLimits`. This is the *single* place that understands the endpoint's
/// JSON shape — the spec's "one file to touch if the API changes".
///
/// Parsing is intentionally tolerant (JSONSerialization + key plucking rather
/// than strict Codable): a partial or reshaped response degrades to whatever
/// fields we recognise rather than failing wholesale. Returns `nil` only when
/// the payload is not JSON or contains none of the fields we understand.
public enum LiveLimitsDecoder {

    public static func decode(_ data: Data) -> LiveLimits? {
        guard !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data),
              let obj = root as? [String: Any]
        else { return nil }

        let five = obj.window(forAnyOf: ["five_hour", "fiveHour", "5h"])
        let week = obj.window(forAnyOf: ["seven_day", "sevenDay", "weekly", "7d"])
        let credits = obj.credits()

        let live = LiveLimits(
            fiveHourPercent: five?.utilization,
            weeklyPercent: week?.utilization,
            fiveHourResetsAt: five?.resetsAt,
            weeklyResetsAt: week?.resetsAt,
            creditBalanceMinorUnits: credits.balanceMinorUnits,
            creditUsedMinorUnits: credits.usedMinorUnits,
            currency: credits.currency
        )

        // Nothing recognised → treat as "no live data" rather than an empty shell.
        let empty = live.fiveHourPercent == nil && live.weeklyPercent == nil
            && live.creditBalanceMinorUnits == nil && live.creditUsedMinorUnits == nil
        return empty ? nil : live
    }
}

/// One rate-limit window parsed from the response.
private struct DecodedWindow {
    var utilization: Double?
    var resetsAt: Date?
}

/// Extra-usage credit figures, normalised to the app's minor-unit (cents) model.
private struct DecodedCredits {
    var balanceMinorUnits: Int?
    var usedMinorUnits: Int?
    var currency: String?
}

private extension Dictionary where Key == String, Value == Any {

    /// Reads the first present window object under any of the given aliases.
    func window(forAnyOf keys: [String]) -> DecodedWindow? {
        guard let raw = keys.lazy.compactMap({ self[$0] as? [String: Any] }).first
        else { return nil }
        let util = raw.doubleForAnyOf(["utilization", "used_pct", "usedPct", "percent"])
        return DecodedWindow(utilization: util.map(normalizeFraction),
                             resetsAt: raw.dateForAnyOf(["resets_at", "resetsAt", "reset"]))
    }

    /// Extra-usage credits. The live endpoint reports these under `extra_usage`
    /// as *major-unit* amounts (`used_credits`, `monthly_limit`) alongside a
    /// `decimal_places` and an `is_enabled` flag — distinct from the rest of
    /// Claude's data, which names pre-scaled amounts `*_minor_units`. We surface
    /// them only when `is_enabled` is true, so a disabled account shows no live
    /// credit line rather than a misleading $0. Falls back to the pre-scaled
    /// `credits` shape (spec / older responses) when `extra_usage` is absent.
    func credits() -> DecodedCredits {
        if let extra = self["extra_usage"] as? [String: Any] {
            guard (extra["is_enabled"] as? NSNumber)?.boolValue == true else {
                return DecodedCredits()
            }
            let used = extra.majorAmountAsMinorUnits("used_credits")
            let limit = extra.majorAmountAsMinorUnits("monthly_limit")
            // Balance shown is what's left of the cap; with no cap we only know spend.
            let balance = (limit != nil && used != nil) ? limit! - used! : limit
            return DecodedCredits(balanceMinorUnits: balance, usedMinorUnits: used,
                                  currency: extra["currency"] as? String)
        }
        if let credits = self["credits"] as? [String: Any] {
            return DecodedCredits(
                balanceMinorUnits: credits.intForAnyOf(["balance_minor_units", "balanceMinorUnits", "balance"]),
                usedMinorUnits: credits.intForAnyOf(["used_minor_units", "usedMinorUnits", "used"]),
                currency: credits["currency"] as? String)
        }
        return DecodedCredits()
    }

    /// A major-unit money amount (e.g. dollars) → minor units (cents), matching
    /// `MoneyFormat`'s ÷100 display convention.
    func majorAmountAsMinorUnits(_ key: String) -> Int? {
        guard let n = self[key] as? NSNumber else { return nil }
        return Int((n.doubleValue * 100).rounded())
    }

    func doubleForAnyOf(_ keys: [String]) -> Double? {
        for k in keys { if let n = self[k] as? NSNumber { return n.doubleValue } }
        return nil
    }

    func intForAnyOf(_ keys: [String]) -> Int? {
        for k in keys { if let n = self[k] as? NSNumber { return n.intValue } }
        return nil
    }

    func dateForAnyOf(_ keys: [String]) -> Date? {
        for k in keys {
            if let s = self[k] as? String, let d = LiveLimitsDateParser.date(from: s) { return d }
            if let n = self[k] as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        }
        return nil
    }
}

/// The endpoint reports `utilization` on a 0–100 percentage scale — confirmed
/// against live responses (`five_hour: 7.0` = 7%, `seven_day: 1.0` = 1%).
/// Normalise to a 0…1(+) fraction so `LimitEngine`/UI always see a fraction.
/// (An earlier `v > 1 ? v/100 : v` guess wrongly read a real 1% weekly as 100%.)
private func normalizeFraction(_ v: Double) -> Double { v / 100 }

/// ISO-8601 parsing, with and without fractional seconds.
private enum LiveLimitsDateParser {
    static func date(from s: String) -> Date? {
        let a = ISO8601DateFormatter()
        if let d = a.date(from: s) { return d }
        let b = ISO8601DateFormatter()
        b.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return b.date(from: s)
    }
}
