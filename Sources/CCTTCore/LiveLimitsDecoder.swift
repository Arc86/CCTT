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
        let credits = obj["credits"] as? [String: Any]

        let live = LiveLimits(
            fiveHourPercent: five?.utilization,
            weeklyPercent: week?.utilization,
            fiveHourResetsAt: five?.resetsAt,
            weeklyResetsAt: week?.resetsAt,
            creditBalanceMinorUnits: credits?.intForAnyOf(["balance_minor_units", "balanceMinorUnits", "balance"]),
            creditUsedMinorUnits: credits?.intForAnyOf(["used_minor_units", "usedMinorUnits", "used"]),
            currency: credits?["currency"] as? String
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

private extension Dictionary where Key == String, Value == Any {

    /// Reads the first present window object under any of the given aliases.
    func window(forAnyOf keys: [String]) -> DecodedWindow? {
        guard let raw = keys.lazy.compactMap({ self[$0] as? [String: Any] }).first
        else { return nil }
        let util = raw.doubleForAnyOf(["utilization", "used_pct", "usedPct", "percent"])
        return DecodedWindow(utilization: util.map(normalizeFraction),
                             resetsAt: raw.dateForAnyOf(["resets_at", "resetsAt", "reset"]))
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

/// A percentage may arrive as a 0–1 fraction or a 0–100 whole number; normalise
/// to a fraction so `LimitEngine`/UI always see 0…1(+).
private func normalizeFraction(_ v: Double) -> Double { v > 1 ? v / 100 : v }

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
