import Testing
import Foundation
@testable import CCTTCore

/// 2026-07-17T14:00:00Z — the window runs 09:00–14:00.
private let windowEnd = Date(timeIntervalSince1970: 1_784_296_800)
private let fiveHours: TimeInterval = 5 * 3600
private var windowStart: Date { windowEnd.addingTimeInterval(-fiveHours) }

/// `now` at `fraction` through the window.
private func at(_ fraction: Double) -> Date {
    windowStart.addingTimeInterval(fiveHours * fraction)
}

@Test func onTrackWhenUsageTracksElapsedTime() {
    // 40% used, 50% elapsed → ratio 0.8 → finishes the window at 80% of cap.
    let p = Pace.evaluate(percent: 0.4, windowEnd: windowEnd, duration: fiveHours,
                          now: at(0.5), provenance: .estimated)
    #expect(p?.status == .onTrack)
    #expect(abs((p?.ratio ?? 0) - 0.8) < 0.0001)
    #expect(p?.exhaustsAt == nil)          // never runs out before reset
}

@Test func atRiskWhenProjectedToJustExhaust() {
    // 55% used, 50% elapsed → ratio 1.1 → between 1.0 and riskThreshold.
    let p = Pace.evaluate(percent: 0.55, windowEnd: windowEnd, duration: fiveHours,
                          now: at(0.5), provenance: .estimated)
    #expect(p?.status == .atRisk)
    #expect(p?.exhaustsAt != nil)
}

@Test func willExceedAtOrAboveTheRiskThreshold() {
    // 60% used, 50% elapsed → ratio 1.2 → exactly riskThreshold (inclusive).
    let p = Pace.evaluate(percent: 0.6, windowEnd: windowEnd, duration: fiveHours,
                          now: at(0.5), provenance: .estimated)
    #expect(p?.status == .willExceed)
    #expect(abs((p?.ratio ?? 0) - 1.2) < 0.0001)
}

@Test func ratioOfExactlyOneIsAtRiskNotWillExceed() {
    let p = Pace.evaluate(percent: 0.5, windowEnd: windowEnd, duration: fiveHours,
                          now: at(0.5), provenance: .estimated)
    #expect(p?.status == .atRisk)
    // Projected to land exactly on the cap at windowEnd — not strictly before it.
    #expect(p?.exhaustsAt == nil)
}

@Test func exhaustsAtProjectsTheRunOutMoment() {
    // 60% used at 50% elapsed. Rate = 0.6 per 2.5h → remaining 0.4 takes 1h40m.
    let now = at(0.5)
    let p = Pace.evaluate(percent: 0.6, windowEnd: windowEnd, duration: fiveHours,
                          now: now, provenance: .estimated)
    let expected = now.addingTimeInterval((1.0 - 0.6) * (fiveHours * 0.5) / 0.6)
    #expect(abs((p?.exhaustsAt ?? .distantPast).timeIntervalSince(expected)) < 1)
}

@Test func alreadyOverTheLimitExhaustsNow() {
    let now = at(0.5)
    let p = Pace.evaluate(percent: 1.2, windowEnd: windowEnd, duration: fiveHours,
                          now: now, provenance: .live)
    #expect(p?.status == .willExceed)
    #expect(p?.exhaustsAt == now)
}

@Test func nilAtZeroUsage() {
    // No usage means no rate — there is nothing to project.
    #expect(Pace.evaluate(percent: 0, windowEnd: windowEnd, duration: fiveHours,
                          now: at(0.5), provenance: .estimated) == nil)
}

@Test func nilOutsideTheWindow() {
    #expect(Pace.evaluate(percent: 0.5, windowEnd: windowEnd, duration: fiveHours,
                          now: windowStart, provenance: .estimated) == nil)
    #expect(Pace.evaluate(percent: 0.5, windowEnd: windowEnd, duration: fiveHours,
                          now: windowEnd, provenance: .estimated) == nil)
    #expect(Pace.evaluate(percent: 0.5, windowEnd: windowEnd, duration: fiveHours,
                          now: windowEnd.addingTimeInterval(60), provenance: .estimated) == nil)
}

@Test func nilOnNonPositiveDuration() {
    #expect(Pace.evaluate(percent: 0.5, windowEnd: windowEnd, duration: 0,
                          now: at(0.5), provenance: .estimated) == nil)
}

@Test func provenanceIsInheritedNeverInvented() {
    let est = Pace.evaluate(percent: 0.6, windowEnd: windowEnd, duration: fiveHours,
                            now: at(0.5), provenance: .estimated)
    #expect(est?.provenance == .estimated)
    let live = Pace.evaluate(percent: 0.6, windowEnd: windowEnd, duration: fiveHours,
                             now: at(0.5), provenance: .live)
    #expect(live?.provenance == .live)
}
