# CCTT — Claude Code Token Tracker

Native macOS **menu-bar-only** app showing Claude Code token spend vs. plan limits, plus
detailed breakdowns of where tokens go. Read-only observer of Claude Code's local data.

**Full design:** [docs/superpowers/specs/2026-07-08-cctt-token-tracker-design.md](docs/superpowers/specs/2026-07-08-cctt-token-tracker-design.md).
This file is the quick-reference; the spec is the source of truth. Keep them consistent.

## Tech stack
- Swift + SwiftUI, `MenuBarExtra` (`.window` style) + a `Window` scene for details + a
  Settings scene. Swift Charts for graphs. No external runtime dependencies.
- Targets macOS (menu-bar-only: no dock icon — `LSUIElement`).

## Architecture (4 units below the UI)
Everything below the two stores is pure and file-driven → testable without a running app.
- **Ingestor** — tails `~/.claude/projects/**/*.jsonl`, parses new bytes into
  `UsageEvent`s via an incremental byte-offset cache, de-dups on `(requestId, messageId)`.
- **UsageStore** — aggregates events into rollups (project/model/session/agent/window/
  context). Pure functions in, `@Published` snapshot out.
- **PlanDetector** — reads `~/.claude.json` `oauthAccount` → `PlanConfig`
  (subscription / API / enterprise).
- **LimitEngine** — plan + usage → `PlanStatus` (%, resets, optional `creditsStatus`).
  Hybrid: live via `LiveLimitProvider`, else tier-estimate.
- **UI** — Glance, popover, detail window (5 tabs), settings. Observes the two stores.

## Key data sources (read-only)
- **Usage:** `~/.claude/projects/**/*.jsonl` — lines where `type=="assistant"` &&
  `message.usage`. Total context = `input_tokens + cache_read + cache_creation`.
- **Plan/account:** `~/.claude.json` → `oauthAccount` (`billingType`, `organizationType`,
  `organizationRateLimitTier`, `hasExtraUsageEnabled`), `overageCreditGrantCache`.
- **Live limits:** OAuth token (Keychain) → rate-limit endpoint. Opt-in, prompted on
  first launch. Isolated behind `LiveLimitProvider`. App fully works on estimates alone.

## Non-negotiable principles
- **Data provenance is always explicit.** Never show measured and estimated numbers
  ambiguously. `.measured` (plain) / `.derived` ("≈ cost") / `.live` (green) /
  `.estimated` ("~est") / `.billed` (real credit money). See spec §7.
- **Never lie or crash on bad input.** Malformed lines skipped + counted; missing data →
  friendly empty state; live failure → auto-degrade to estimated with a badge flip.
- **User-configurable show/hide** for tabs, popover sections, glance content, unit
  ($ ⇄ tokens).
- Read-only: CCTT never writes to `~/.claude/` or influences Claude Code.

## Testing
TDD — tests before implementation. Fixture `.jsonl` and `~/.claude.json` files drive
Ingestor/PlanDetector; injected clock + `LiveLimitProvider` stub make UsageStore/
LimitEngine deterministic (`Date.now` is nondeterministic — always inject the clock).
UI via SwiftUI previews + snapshot tests across live/estimated/credits/empty/degraded.

## Conventions
- One unit per file/folder; keep the four units decoupled through the value types
  (`UsageEvent`, `Rollup`, `PlanConfig`, `PlanStatus`, `UsageSnapshot`, `Provenance`).
- Parsing/aggregation off the main actor; only publish the aggregated snapshot to UI.

## Build / run / test
- Build: `swift build`
- Run (menu-bar app): `swift run CCTTApp`
- Test: `swift test` (Swift Testing; filter with `--filter <TestSuiteOrName>`)

## Status
Plan 4 (live limits, credits, alerts, Settings, onboarding) complete. The live
path is fully isolated and TDD'd in `CCTTCore`: `LiveLimitsDecoder` parses the
(unofficial) rate-limit endpoint JSON; `ClaudeCredentialsDecoder` +
`KeychainCredentialsSource` read Claude Code's OAuth token read-only from the
Keychain (`CredentialsSource` seam); `NetworkLiveLimitProvider` composes them
over an injectable `HTTPTransport` and degrades to `nil` on any failure;
`GatedLiveLimitProvider` makes live strictly opt-in (no Keychain/network until
enabled). `AlertEngine` is a pure edge-triggered evaluator (`AlertState` is
Codable/persisted; fires once per threshold crossing, re-arms on window reset).
`AppSettings` is one lenient-Codable value type (manual plan override, API
budget, manual caps, thresholds, hidden tabs); `LimitEngine.status` now honors
a `manualCaps` fallback and a `settingsProvider` on `PlanStore`. App shell (thin):
`SettingsStore`/`AppSettingsStorage` (UserDefaults), a `⌘,` `TabView` Settings
scene (Plan/Live/Alerts/Display/Data), first-launch `OnboardingView`, and
`NotificationManager` (guarded `UNUserNotificationCenter` shell over
`AlertEngine`). Popover renders credits (`MoneyFormat`, `.billed`/`.estimated`)
and live reset countdowns. 142 tests green.

Plan 3 (detail UI) complete: a resizable **detail `Window`** opened from the
popover shows five Swift-Charts tabs — Projects, Models, Agents/Skills/Plugins
(Plan 3A, over the pure `breakdown()` builder) and Sessions & Timeline + Context
Windows (Plan 3B, over `timelineSeries`/`sessionSummaries`/`contextSummaries`).
A global **time-range** control and a **$ ⇄ tokens** toggle (persisted via
`DisplayState` + `UserDefaults`) drive every tab; derived $ is attributed
per-event and always carries a "≈" affordance. All range/cost/timeline/context
aggregation is pure and TDD'd in `CCTTCore`; views are thin (previews only).
