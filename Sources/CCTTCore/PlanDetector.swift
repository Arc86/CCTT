import Foundation

/// Classifies the active Claude Code plan from `~/.claude.json` and the
/// process environment. Tolerant: any decode failure yields `.unknown`.
public enum PlanDetector {

    public static func detect(
        configURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PlanConfig {
        let raw = try? decode(configURL)
        let usesApiKey = apiKeyPresent(environment) || (raw?.apiKeyHelper?.isEmpty == false)

        // No account block: API mode if a key is configured, else unknown.
        guard let oa = raw?.oauthAccount else {
            return usesApiKey ? config(kind: .api, source: .detected, raw: raw)
                              : .unknown(source: .fallback)
        }

        let org = oa.organizationType ?? ""
        let kind: PlanKind
        let source: PlanSource
        if usesApiKey {
            kind = .api; source = .detected
        } else if org.hasPrefix("enterprise") {
            kind = .enterprise; source = .detected
        } else if org == "claude_max" || org == "claude_pro" {
            kind = .subscription; source = .detected
        } else {
            kind = .unknown; source = .fallback
        }
        return config(kind: kind, source: source, raw: raw)
    }

    // MARK: - Helpers

    static func apiKeyPresent(_ env: [String: String]) -> Bool {
        if let k = env["ANTHROPIC_API_KEY"], !k.isEmpty { return true }
        return false
    }

    private static func config(kind: PlanKind, source: PlanSource, raw: RawConfig?) -> PlanConfig {
        let oa = raw?.oauthAccount
        return PlanConfig(
            kind: kind,
            rateLimitTier: oa?.organizationRateLimitTier,
            organizationType: oa?.organizationType,
            billingType: oa?.billingType,
            hasExtraUsageEnabled: oa?.hasExtraUsageEnabled ?? false,
            seatTier: oa?.seatTier,
            organizationRole: oa?.organizationRole,
            displayName: oa?.displayName,
            currency: "USD",
            creditGrant: creditGrant(from: raw),
            source: source
        )
    }

    private static func creditGrant(from raw: RawConfig?) -> CreditGrant? {
        guard let raw, let cache = raw.overageCreditGrantCache, !cache.isEmpty else { return nil }
        let entry = raw.oauthAccount?.organizationUuid.flatMap { cache[$0] } ?? cache.values.first
        guard let info = entry?.info else { return nil }
        return CreditGrant(available: info.available ?? false,
                           eligible: info.eligible ?? false,
                           granted: info.granted ?? false,
                           amountMinorUnits: info.amount_minor_units,
                           currency: info.currency)
    }

    private static func decode(_ url: URL) throws -> RawConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RawConfig.self, from: data)
    }

    // MARK: - Raw Codable mirror of ~/.claude.json (only fields we use).

    private struct RawConfig: Decodable {
        let oauthAccount: RawOAuth?
        let overageCreditGrantCache: [String: RawGrant]?
        let apiKeyHelper: String?
    }
    private struct RawOAuth: Decodable {
        let organizationUuid: String?
        let billingType: String?
        let organizationType: String?
        let organizationRateLimitTier: String?
        let hasExtraUsageEnabled: Bool?
        let seatTier: String?
        let organizationRole: String?
        let displayName: String?
    }
    private struct RawGrant: Decodable { let info: RawGrantInfo? }
    private struct RawGrantInfo: Decodable {
        let available: Bool?
        let eligible: Bool?
        let granted: Bool?
        let amount_minor_units: Int?
        let currency: String?
    }
}
