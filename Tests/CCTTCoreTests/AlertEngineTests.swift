import Foundation
import Testing
@testable import CCTTCore

/// Edge-triggered threshold alerts: each threshold fires once when crossed
/// upward, and re-arms only after usage falls back below it (window reset).
struct AlertEngineTests {

    private let thresholds = AlertThresholds(fiveHour: [0.8, 0.95],
                                             weekly: [0.8, 0.95],
                                             credits: [0.8, 0.95])

    @Test func crossingAThresholdFiresOnce() {
        var state = AlertState()
        var out = AlertEngine.evaluate(percents: [.fiveHour: 0.82],
                                       thresholds: thresholds, state: state)
        #expect(out.alerts == [Alert(window: .fiveHour, threshold: 0.8, percent: 0.82)])
        state = out.state

        // Same percent again → no re-fire (latched).
        out = AlertEngine.evaluate(percents: [.fiveHour: 0.82],
                                   thresholds: thresholds, state: state)
        #expect(out.alerts.isEmpty)
    }

    @Test func higherThresholdFiresSeparately() {
        var state = AlertState()
        state = AlertEngine.evaluate(percents: [.fiveHour: 0.82],
                                     thresholds: thresholds, state: state).state
        let out = AlertEngine.evaluate(percents: [.fiveHour: 0.97],
                                       thresholds: thresholds, state: state)
        #expect(out.alerts == [Alert(window: .fiveHour, threshold: 0.95, percent: 0.97)])
    }

    @Test func startingAboveAThresholdFiresImmediately() {
        let out = AlertEngine.evaluate(percents: [.weekly: 0.99],
                                       thresholds: thresholds, state: AlertState())
        // Both thresholds crossed at once; both fire, low-to-high.
        #expect(out.alerts == [Alert(window: .weekly, threshold: 0.8, percent: 0.99),
                               Alert(window: .weekly, threshold: 0.95, percent: 0.99)])
    }

    @Test func fallingBelowRearmsForNextCycle() {
        var state = AlertState()
        state = AlertEngine.evaluate(percents: [.fiveHour: 0.90],
                                     thresholds: thresholds, state: state).state
        // Window resets → usage drops; no alert, but re-arms 0.8.
        var out = AlertEngine.evaluate(percents: [.fiveHour: 0.10],
                                       thresholds: thresholds, state: state)
        #expect(out.alerts.isEmpty)
        state = out.state
        // Climbing again fires 0.8 anew.
        out = AlertEngine.evaluate(percents: [.fiveHour: 0.85],
                                   thresholds: thresholds, state: state)
        #expect(out.alerts == [Alert(window: .fiveHour, threshold: 0.8, percent: 0.85)])
    }

    @Test func windowsAreIndependent() {
        let out = AlertEngine.evaluate(percents: [.fiveHour: 0.82, .weekly: 0.10],
                                       thresholds: thresholds, state: AlertState())
        #expect(out.alerts == [Alert(window: .fiveHour, threshold: 0.8, percent: 0.82)])
    }

    @Test func stateRoundTripsThroughCodableForPersistence() throws {
        let state = AlertEngine.evaluate(percents: [.fiveHour: 0.99],
                                         thresholds: thresholds, state: AlertState()).state
        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(AlertState.self, from: data)
        // A restored state must not re-fire already-latched thresholds.
        let out = AlertEngine.evaluate(percents: [.fiveHour: 0.99],
                                       thresholds: thresholds, state: restored)
        #expect(out.alerts.isEmpty)
    }

    @Test func creditsPercentDerivedFromUsedAndBalance() {
        // 900 used of 1000 total → 0.9 → crosses 0.8.
        let status = PlanStatus(
            kind: .subscription, planLabel: "Max", windows: [],
            credits: CreditsStatus(enabled: true, balanceMinorUnits: 100,
                                   usedThisPeriodMinorUnits: 900, currency: "USD",
                                   provenance: .billed),
            costUSD: nil, provenance: .live, generatedAt: Date(timeIntervalSince1970: 0))
        let percents = AlertEngine.percents(from: status)
        #expect(percents[.credits] == 0.9)
    }
}
