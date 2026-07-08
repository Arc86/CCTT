/// How much to trust a displayed value, and how the UI must label it.
public enum Provenance: Sendable, Equatable {
    case measured   // straight from JSONL token counts — no assumptions
    case derived    // computed from measured data + a bundled table (e.g. $ cost)
    case live       // fetched live from the rate-limit endpoint
    case estimated  // computed against an assumed denominator (tier cap table)
    case billed     // actual money spent (credits) — real, not an estimate
}
