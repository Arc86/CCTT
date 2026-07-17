import Foundation
import Testing
@testable import CCTTCore

struct AppSettingsTests {

    @Test func defaultsAreConservativeAndOptIn() {
        let s = AppSettings()
        #expect(s.liveLimitsEnabled == false)   // live is opt-in (spec §6 auth)
        #expect(s.alertsEnabled == false)        // notifications opt-in too
        #expect(s.manualPlanKind == nil)         // auto-detect by default
        #expect(s.apiMonthlyBudgetUSD == nil)
        #expect(s.thresholds == AlertThresholds.default)
        #expect(s.projectsPathOverride == nil)
        #expect(s.hiddenTabs.isEmpty)
        #expect(s.showPercentInMenuBar == true)   // icon + % shown by default
    }

    @Test func roundTripsThroughCodable() throws {
        var s = AppSettings()
        s.liveLimitsEnabled = true
        s.manualPlanKind = .api
        s.apiMonthlyBudgetUSD = 50
        s.alertsEnabled = true
        s.thresholds = AlertThresholds(fiveHour: [0.5], weekly: [0.9], credits: [0.75])
        s.projectsPathOverride = "/custom/projects"
        s.hiddenTabs = ["contextWindows"]
        s.currencyCode = "EUR"
        s.showPercentInMenuBar = false

        let data = try JSONEncoder().encode(s)
        let restored = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(restored == s)
    }

    /// Forward-compatible: settings persisted by an older build (missing keys)
    /// still decode, filling absent fields with defaults.
    @Test func decodesPartialJSONWithDefaults() throws {
        let json = Data(#"{ "liveLimitsEnabled": true }"#.utf8)
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(s.liveLimitsEnabled == true)
        #expect(s.alertsEnabled == false)
        #expect(s.thresholds == AlertThresholds.default)
        #expect(s.showPercentInMenuBar == true)   // absent key → default true
        #expect(s.exportEnabled == false)         // absent key → default false
    }
}

struct MoneyFormatTests {

    @Test func formatsMinorUnitsWithSymbol() {
        #expect(MoneyFormat.string(minorUnits: 4200, currency: "EUR") == "€42.00")
        #expect(MoneyFormat.string(minorUnits: 500, currency: "USD") == "$5.00")
        #expect(MoneyFormat.string(minorUnits: 1234, currency: "GBP") == "£12.34")
    }

    @Test func unknownCurrencyFallsBackToCodePrefix() {
        #expect(MoneyFormat.string(minorUnits: 1000, currency: "SEK") == "SEK 10.00")
    }

    @Test func handlesZeroAndNil() {
        #expect(MoneyFormat.string(minorUnits: 0, currency: "USD") == "$0.00")
        #expect(MoneyFormat.string(minorUnits: nil, currency: "USD") == "—")
    }
}
