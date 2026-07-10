import Testing
@testable import CCTTCore

@MainActor
@Test func rangeMemoComputesOncePerRangeAndVersion() {
    let memo = RangeMemo<Int>()
    var calls = 0
    func value(_ r: TimeRange, _ v: Int) -> Int {
        memo.value(range: r, version: v) { calls += 1; return calls }
    }

    _ = value(.all, 1)
    _ = value(.all, 1)            // cache hit → no recompute
    #expect(calls == 1)

    _ = value(.last7Days, 1)      // different range → recompute
    #expect(calls == 2)

    _ = value(.all, 1)            // still cached
    #expect(calls == 2)
}

@MainActor
@Test func rangeMemoInvalidatesOnVersionBump() {
    let memo = RangeMemo<Int>()
    var calls = 0
    func value(_ v: Int) -> Int {
        memo.value(range: .all, version: v) { calls += 1; return calls }
    }

    _ = value(1)
    #expect(calls == 1)
    _ = value(2)                  // new version → recompute, drop stale cache
    #expect(calls == 2)
    _ = value(2)                  // cached again
    #expect(calls == 2)
}
