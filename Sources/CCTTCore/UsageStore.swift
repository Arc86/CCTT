import Foundation
import Observation

/// Abstraction over the ingestor so the store can be tested with a stub.
public protocol UsageScanning: Sendable {
    func scan() -> ScanResult
}

/// Owns accumulated usage events and the published aggregated snapshot.
@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshot: UsageSnapshot

    private let scanner: UsageScanning
    private let clock: @Sendable () -> Date
    private var accumulated: [UsageEvent] = []
    private var totalParseErrors = 0

    public init(scanner: UsageScanning, clock: @escaping @Sendable () -> Date) {
        self.scanner = scanner
        self.clock = clock
        self.snapshot = .empty(now: clock())
    }

    /// Pull any new events from the scanner and re-publish the snapshot.
    public func refresh() {
        let result = scanner.scan()
        accumulated.append(contentsOf: result.events)
        totalParseErrors += result.parseErrors
        snapshot = aggregate(events: accumulated,
                             parseErrors: totalParseErrors,
                             now: clock())
    }
}
