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
**Auto-update + start-at-login (2026-07-10):** the app now ships as a real,
notarized `CCTTApp.app` (`packaging/package_app.sh` assembles + embeds
`Sparkle.framework` + deep-signs with the Developer ID; `packaging/release.sh`
notarizes, staples, EdDSA-signs, and appends to `appcast.xml`, fed from
`raw.githubusercontent.com/Arc86/CCTT/main/appcast.xml` with GitHub Release
zip assets). **Sparkle** auto-update (`SparkleUpdater` over
`SPUStandardUpdaterController`, behind the `SoftwareUpdating` seam) and
**start-at-login** (`SystemLoginItem` over `SMAppService.mainApp`, behind
`LoginItemControlling` with a revert-on-error `LoginItemToggle`) surface in a
new **General** settings pane plus a popover "Check for Updates…". Both controls
degrade to disabled (with a caption) on unbundled `run.sh` dev launches, gated
by `AppBundling.isBundled`. Version display resolves via `AppVersion` (bundle
short version → `coreVersion` fallback). `CCTTCore` stays dependency-free; Sparkle
is a `CCTTApp`-only dependency. New pure units TDD'd in Core. Packaging runbook:
`packaging/README.md`. 195 tests green.

**Settings — Claude Desktop redesign (2026-07-10):** the `⌘,` Settings scene was
re-styled from the System Settings idiom (a `NavigationSplitView`, which insisted on
an inset floating sidebar with a disconnected horizontal titlebar) into a **fully
custom flush two-pane layout** matching Claude Desktop's app sidebar. `SettingsView`
is now a plain `HStack`: a fixed-width sidebar backed by a real `.sidebar`
`NSVisualEffectView` (`SidebarMaterial`) + a `Divider` + the grouped-`Form` content.
The Settings `Window` scene uses `.windowStyle(.hiddenTitleBar)` and the layout
`.ignoresSafeArea(.container, edges: .top)`, so the sidebar runs flush to both edges
and full-height with the **traffic lights floating over it** (unified titlebar). The
sidebar keeps the compact `AppIdentityHeader` (gradient gauge tile + plan label) and
a **centred** version footer; rows (`SidebarRow`) are custom buttons with smaller
coloured icon tiles (`SidebarIcon`, 22pt) + **13pt labels** — selected rows take the
system **accent** fill with a white label (native source-list idiom), hover a subtle
neutral tint (top padding clears the traffic lights). Each content pane gets a bold
section title above its native grouped `Form` (skipped for About). A sixth sidebar
item, **About** (`AboutPane`), is a centred identity card: the app logo,
"Claude Code Token Tracker", the tagline *"Keeping tabs on your token tab."*, version,
and a read-only-observer note. **Brand art** ships as bundled resources
(`Sources/CCTTApp/Resources/`, `resources: [.process(...)]` in Package.swift, loaded
via `Bundle.module` through the `Brand` enum): `CCTTLogo.png` (full app icon — mascot
+ CCTT wordmark on a white rounded tile, used in About and set as
`NSApp.applicationIconImage`) and `CCTTMark.png` (mascot-only tile for the sidebar
header). Both were composited from the source art (`~/Desktop/logo2.png`) onto white
rounded tiles so they stay legible in dark mode. All bindings/logic unchanged. 188
tests green.

**Insight Dashboard redesign (2026-07-09):** the detail window was rebuilt from a
top-tab `TabView` into a **sidebar dashboard** (imported from the Claude Design
project "CCTT Insight Dashboard"). `DetailView` is now a `NavigationSplitView`
with a Breakdowns + Plan sidebar (`SidebarItem`), `navigationTitle`/`subtitle`, a
toolbar range+unit control, and a per-window appearance override
(`DisplayState.appearance`). A shared `HeroHeader` (range total, trend pill,
sparkline, sessions/turns) tops every breakdown pane. Reusable primitives live in
`Dashboard/DashboardKit.swift` (`DashCard`, `RankedBarRow`, `Donut`, `MeterBar`,
`DeltaPill`, `StatusPill`, `CalloutBanner`, `CompositionRow`, palette/`Dash`
tokens); the six panes (`ProjectsBody`/`ModelsBody`/`AgentsBody`/`SessionsBody`/
`ContextBody`/`PlanBody` + lightweight table) are in `Dashboard/DashboardTabs.swift`.
The new **Plan** pane renders `PlanStore.status` windows as meter cards. All panes
reuse the existing pure builders; the one new aggregation is `tokenDelta`
(period-over-period, TDD'd, `nil` for `.all`/`.thisWeek`/no-baseline). Views stay
thin (previews only). 188 tests green.

Post-Plan-4 reliability/insight pass (adapted from `phuryn/claude-usage`,
2026-07-09): parsed events now persist to a durable append-only `EventStore`
(`events.jsonl`) loaded by `UsageStore` at launch, so **history survives restart**
(previously the offset cache persisted read positions while events were
memory-only → relaunch dropped all history). `deduplicated` now keeps the **last**
line per `(requestId, messageId)` — Claude Code streams a message across lines and
only the last carries the true `output_tokens`; keep-first undercounted output.
Unpriced models surface as **"n/a"** (via `CostedRollup.unpricedTokens` /
`Breakdown.unpricedTokens`) instead of a silent $0. New insights: an `HourProfile`
hour-of-day chart with the estimated weekly-limit window shaded, a git-branch
breakdown (`Breakdown.byBranch`), a turns/sessions stat bar, and a session
Duration column. See `docs/open-items.md` for the follow-ups. 163 tests green.

**Detail-window performance (2026-07-09):** switching tabs was ~670 ms at "All"
(60k events) because every switch re-derived all five builders on the main actor.
Now: one `deduplicated` pass per data-version shared across builders (`*(deduped:)`
overloads), per-`TimeRange` output memoization (`RangeMemo`, invalidated only when
new events arrive), and the two heavy tabs (Sessions/Context) derive data only
while front. Measured: switch 670 ms → 0 ms; fresh-tab first view 350 ms → ~130 ms.
Remaining follow-up: move the first-build aggregation off the main actor.

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
and live reset countdowns.

Plan 3 (detail UI) complete: a resizable **detail `Window`** opened from the
popover shows five Swift-Charts tabs — Projects, Models, Agents/Skills/Plugins
(Plan 3A, over the pure `breakdown()` builder) and Sessions & Timeline + Context
Windows (Plan 3B, over `timelineSeries`/`sessionSummaries`/`contextSummaries`).
A global **time-range** control and a **$ ⇄ tokens** toggle (persisted via
`DisplayState` + `UserDefaults`) drive every tab; derived $ is attributed
per-event and always carries a "≈" affordance. All range/cost/timeline/context
aggregation is pure and TDD'd in `CCTTCore`; views are thin (previews only).
