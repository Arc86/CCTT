import Foundation

/// Per-`TimeRange` memoization guarded by a monotonic data-version stamp.
///
/// The detail window re-derives every builder (breakdown, timeline, sessions,
/// hourly profile, context) on each `body` evaluation — and `body` re-runs on
/// every tab switch, toolbar tweak, and 20-second refresh. Without memoization
/// each of those re-scanned all retained events from scratch on the main actor
/// (60k+ events × 5 builders), which is what made tab switching janky at the
/// "All" range. Here the first call for a `(range, version)` computes; every
/// later call at the same version is an O(1) dictionary hit. Bumping the version
/// (only when new events actually arrive) drops the whole cache so stale data is
/// never served.
///
/// Not `Sendable`: instances live only inside the `@MainActor` `UsageStore`, so
/// all access is already serialized to the main actor.
final class RangeMemo<Value> {
    private var version = Int.min
    private var cache: [TimeRange: Value] = [:]

    func value(range: TimeRange, version: Int, _ compute: () -> Value) -> Value {
        if version != self.version {
            cache.removeAll(keepingCapacity: true)
            self.version = version
        }
        if let hit = cache[range] { return hit }
        let fresh = compute()
        cache[range] = fresh
        return fresh
    }
}
