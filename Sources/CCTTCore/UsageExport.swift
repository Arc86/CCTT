import Foundation

/// The public, versioned status document CCTT publishes for external consumers —
/// principally a Claude Code statusline, which shells out and parses it on every
/// render.
///
/// Deliberately *not* a dump of `UsageSnapshot`: per-project and per-model
/// breakdowns are excluded so our internal aggregation shapes never become a
/// public contract. Bump `schemaVersion` for any breaking change to these keys.
public enum UsageExport {
    public static let schemaVersion = 1

    public static func encode(_ status: PlanStatus) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Document(status))
    }
}

// MARK: - Wire format

/// The on-disk shape. Kept separate from `PlanStatus` so the public contract can
/// stay stable while internal types evolve.
private struct Document: Encodable {
    let schemaVersion: Int
    let generatedAt: Date
    let plan: Plan
    let headlinePercent: Double?
    let provenance: String
    let windows: [Window]
    let credits: Credits?
    let spendLimit: SpendLimit?
    /// When the live sample behind a `.live` status was actually fetched. `nil`
    /// when live limits are off or no live sample has ever landed.
    let liveAsOf: Date?
    /// Health of the live path, or `nil` when live limits are disabled. A
    /// statusline consumer needs this to tell a fresh `.live` reading apart
    /// from `StickyLiveLimitProvider` serving a stale-but-real one indefinitely
    /// under `.rateLimited`/`.degraded` — otherwise the ever-refreshing
    /// `generatedAt` above wrongly implies the number itself is current.
    let liveHealth: String?

    init(_ s: PlanStatus) {
        schemaVersion = UsageExport.schemaVersion
        generatedAt = s.generatedAt
        plan = Plan(label: s.planLabel, kind: Names.plan(s.kind))
        headlinePercent = s.headlinePercent
        provenance = Names.provenance(s.provenance)
        windows = s.windows.map(Window.init)
        credits = s.credits.map(Credits.init)
        spendLimit = s.spendLimit.map(SpendLimit.init)
        liveAsOf = s.liveAsOf
        liveHealth = s.liveHealth.map(Names.liveHealth)
    }

    struct Plan: Encodable { let label: String; let kind: String }

    struct Window: Encodable {
        let kind: String
        let percent: Double?
        let usedTokens: Int
        let capTokens: Int?
        let resetsAt: Date?
        let provenance: String
        let pace: PaceDTO?

        init(_ w: WindowStatus) {
            kind = Names.window(w.kind)
            percent = w.percent
            usedTokens = w.usedTokens
            capTokens = w.capTokens
            resetsAt = w.resetsAt
            provenance = Names.provenance(w.provenance)
            pace = w.pace.map(PaceDTO.init)
        }
    }

    struct PaceDTO: Encodable {
        let ratio: Double
        let status: String
        let exhaustsAt: Date?

        init(_ p: Pace) {
            ratio = p.ratio
            status = Names.pace(p.status)
            exhaustsAt = p.exhaustsAt
        }
    }

    struct Credits: Encodable {
        let balanceMinorUnits: Int?
        let usedThisPeriodMinorUnits: Int?
        let currency: String
        let provenance: String

        init(_ c: CreditsStatus) {
            balanceMinorUnits = c.balanceMinorUnits
            usedThisPeriodMinorUnits = c.usedThisPeriodMinorUnits
            currency = c.currency
            provenance = Names.provenance(c.provenance)
        }
    }

    struct SpendLimit: Encodable {
        let spentMinorUnits: Int
        let capMinorUnits: Int
        let percent: Double
        let resetsAt: Date?
        let currency: String
        let provenance: String

        init(_ s: SpendLimitStatus) {
            spentMinorUnits = s.spentMinorUnits
            capMinorUnits = s.capMinorUnits
            percent = s.percent
            resetsAt = s.resetsAt
            currency = s.currency
            provenance = Names.provenance(s.provenance)
        }
    }
}

/// Stable public strings for our internal enums. These are the contract: never
/// rename one without bumping `UsageExport.schemaVersion`.
private enum Names {
    static func provenance(_ p: Provenance) -> String {
        switch p {
        case .measured:  return "measured"
        case .derived:   return "derived"
        case .live:      return "live"
        case .estimated: return "estimated"
        case .billed:    return "billed"
        }
    }

    static func window(_ k: WindowKind) -> String {
        switch k {
        case .fiveHour: return "fiveHour"
        case .weekly:   return "weekly"
        case .month:    return "month"
        }
    }

    static func pace(_ s: PaceStatus) -> String {
        switch s {
        case .onTrack:    return "onTrack"
        case .atRisk:     return "atRisk"
        case .willExceed: return "willExceed"
        }
    }

    static func plan(_ k: PlanKind) -> String {
        switch k {
        case .subscription: return "subscription"
        case .api:          return "api"
        case .enterprise:   return "enterprise"
        case .unknown:      return "unknown"
        }
    }

    /// `.rateLimited`'s `until` is deliberately dropped — the export stays a
    /// flat string per case, and `until` isn't actionable for a statusline.
    static func liveHealth(_ h: LiveHealth) -> String {
        switch h {
        case .ok:                return "ok"
        case .rateLimited:       return "rateLimited"
        case .needsReauth:       return "needsReauth"
        case .degraded:          return "degraded"
        }
    }
}

// MARK: - Writer

/// Publishes the status document to disk.
///
/// Writes atomically (temp + rename) because the consumer parses on every
/// statusline render and must never observe a half-written file. It writes on
/// every refresh — even when the status hasn't changed — because `generatedAt`
/// always changes on a poll; skipping unchanged writes would either be dead code
/// (byte comparison always differs) or, if `generatedAt` were excluded from the
/// comparison, would turn the file's mtime into "when the status last changed",
/// leaving a consumer unable to tell a steady state from a dead CCTT.
public struct UsageExportWriter: Sendable {
    private let url: URL

    public init(url: URL = DefaultPaths.exportURL) { self.url = url }

    public func write(_ status: PlanStatus) throws {
        let data = try UsageExport.encode(status)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Remove the published file (the user switched the export off). Safe to call
    /// when it does not exist.
    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
