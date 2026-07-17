import Foundation

/// Live rate-limit values fetched from Claude Code's status endpoint.
/// Every field is optional so a partial response still degrades gracefully.
public struct LiveLimits: Sendable, Equatable, Codable {
    public var fiveHourPercent: Double?
    public var weeklyPercent: Double?
    public var fiveHourResetsAt: Date?
    public var weeklyResetsAt: Date?
    public var creditBalanceMinorUnits: Int?
    public var creditUsedMinorUnits: Int?
    public var currency: String?
    /// When the underlying network fetch that produced these numbers actually
    /// succeeded. Stamped by `NetworkLiveLimitProvider` on success and preserved
    /// through the sticky/persistent cache, so the UI can show the sample's age
    /// ("Live · 12m ago") when a fresh poll is failing. `nil` for values that
    /// never came off the wire (tests, hand-built samples).
    public var observedAt: Date?

    public init(fiveHourPercent: Double? = nil, weeklyPercent: Double? = nil,
                fiveHourResetsAt: Date? = nil, weeklyResetsAt: Date? = nil,
                creditBalanceMinorUnits: Int? = nil, creditUsedMinorUnits: Int? = nil,
                currency: String? = nil, observedAt: Date? = nil) {
        self.fiveHourPercent = fiveHourPercent; self.weeklyPercent = weeklyPercent
        self.fiveHourResetsAt = fiveHourResetsAt; self.weeklyResetsAt = weeklyResetsAt
        self.creditBalanceMinorUnits = creditBalanceMinorUnits
        self.creditUsedMinorUnits = creditUsedMinorUnits; self.currency = currency
        self.observedAt = observedAt
    }
}

/// Single seam for all live-limit access. The whole app works without it.
public protocol LiveLimitProvider: Sendable {
    func fetch() async -> LiveFetchResult
}

/// Plan-2 default: reports unavailable, so the engine uses the estimate path.
public struct UnavailableLiveLimitProvider: LiveLimitProvider {
    public init() {}
    public func fetch() async -> LiveFetchResult { .disabled }
}

/// Test / dev provider returning a fixed value.
public struct StaticLiveLimitProvider: LiveLimitProvider {
    public let value: LiveLimits?
    public init(_ value: LiveLimits?) { self.value = value }
    public func fetch() async -> LiveFetchResult {
        guard let value else { return .disabled }
        return LiveFetchResult(limits: value, outcome: .success)
    }
}

/// Wraps a real provider behind a runtime on/off gate (the user's "Live limits"
/// setting). While disabled it reports `.disabled` without consulting the wrapped
/// provider — so no Keychain access or network call happens until opted in.
public struct GatedLiveLimitProvider: LiveLimitProvider {
    private let wrapped: LiveLimitProvider
    private let isEnabled: @Sendable () -> Bool

    public init(wrapping wrapped: LiveLimitProvider, isEnabled: @escaping @Sendable () -> Bool) {
        self.wrapped = wrapped; self.isEnabled = isEnabled
    }

    public func fetch() async -> LiveFetchResult {
        isEnabled() ? await wrapped.fetch() : .disabled
    }
}

/// Serves the last successful `LiveLimits` through failures of the wrapped source.
/// The (unofficial) rate-limit endpoint 429s aggressively — often for extended
/// stretches — and its tier-estimate fallback is wildly off, so we prefer a *stale
/// but real* live figure to a guessed one, indefinitely. The sample's `observedAt`
/// travels with it, and (since the outcome channel was added) so does the reason
/// the fresh fetch failed, letting the UI show both the number and its health
/// rather than silently presenting old data as current.
///
/// The last-good value is persisted to `cacheURL` (when provided) so the number
/// survives an app restart while the endpoint is still throttled. Place this
/// *inside* the gate so disabling live still cuts over to estimates immediately.
public actor StickyLiveLimitProvider: LiveLimitProvider {
    private let wrapped: LiveLimitProvider
    private let cacheURL: URL?
    private var lastGood: LiveLimits?

    /// - Parameter cacheURL: where to persist the last-good sample across
    ///   restarts. `nil` keeps the cache in-memory only (tests).
    public init(wrapping wrapped: LiveLimitProvider, cacheURL: URL? = nil) {
        self.wrapped = wrapped
        self.cacheURL = cacheURL
        self.lastGood = cacheURL.flatMap(Self.load)
    }

    public func fetch() async -> LiveFetchResult {
        let result = await wrapped.fetch()
        if case .success = result.outcome, let fresh = result.limits {
            lastGood = fresh
            persist(fresh)
            return result
        }
        // Opting out must cut over to estimates at once — never serve a cached
        // live number once the gate is closed.
        if case .disabled = result.outcome { return result }
        // No fresh reading: keep serving the last real one (with its original age)
        // rather than degrading to the tier estimate, but pass the reason along.
        return LiveFetchResult(limits: lastGood, outcome: result.outcome)
    }

    private func persist(_ value: LiveLimits) {
        guard let cacheURL, let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func load(_ url: URL) -> LiveLimits? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LiveLimits.self, from: data)
    }
}
