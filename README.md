# CCTT — Claude Code Token Tracker

A native macOS **menu-bar app** that shows your Claude Code token spend against your
plan limits, and breaks down exactly where those tokens go — by project, model, agent,
session, and context window.

CCTT is a **read-only observer** of Claude Code's local data. It never writes to
`~/.claude/` and never influences Claude Code in any way.

> **Status:** early development (`0.1.0`). Fully functional; not yet packaged for
> distribution. See [Roadmap](#roadmap).

---

## Highlights

- **At-a-glance menu-bar gauge** — current usage vs. limit, always visible, no dock icon.
- **Popover summary** — plan status, reset countdowns, and credit balance (when live
  limits are enabled).
- **Insight dashboard** — a resizable detail window with a sidebar of breakdowns:
  Projects · Models · Agents/Skills/Plugins · Sessions · Context Windows · Plan.
  Each pane has a shared hero header (range total, trend, sparkline) and a global
  time-range + **$ ⇄ tokens** toggle.
- **Hybrid limits** — uses live rate-limit data when you opt in, and falls back to
  tier estimates otherwise. The app is fully usable on estimates alone.
- **Explicit data provenance** — measured, derived (`≈`), live, estimated (`~est`),
  and billed (real credit money) values are always visually distinguished. CCTT never
  shows a measured and an estimated number ambiguously.
- **Alerts** — edge-triggered notifications when you cross a usage threshold, re-armed
  on each window reset.
- **History survives restart** — parsed events persist to a durable append-only store,
  so your usage history isn't lost when you quit the app.

---

## How it works

CCTT reads three local data sources, all read-only:

| Source | Location | Used for |
| --- | --- | --- |
| **Usage** | `~/.claude/projects/**/*.jsonl` | Token counts per request (`type == "assistant"` lines with `message.usage`). Total context = `input_tokens + cache_read + cache_creation`. |
| **Plan / account** | `~/.claude.json` → `oauthAccount` | Detecting your plan (subscription / API / enterprise) and credit grants. |
| **Live limits** *(opt-in)* | OAuth token from the Keychain → rate-limit endpoint | Real-time limit windows and reset times. Prompted on first launch; never accessed until enabled. |

### Architecture

Everything below the UI is pure and file-driven, so it's testable without a running app.

- **Ingestor** — tails the project `.jsonl` files, parsing only new bytes via a
  byte-offset cache, de-duping on `(requestId, messageId)`.
- **UsageStore** — aggregates events into rollups (project / model / session / agent /
  window / context). Pure functions in, published snapshot out.
- **PlanDetector** — reads `~/.claude.json` into a `PlanConfig`.
- **LimitEngine** — turns plan + usage into a `PlanStatus` (usage %, resets, optional
  credit status), live when available and tier-estimated otherwise.
- **UI** — the glance label, popover, detail dashboard, and settings observe the two
  stores.

The core logic lives in the `CCTTCore` library; the SwiftUI app shell lives in `CCTTApp`.

---

## Requirements

- macOS 15 (Sequoia) or later
- Swift 6 toolchain (Xcode 16+)
- Claude Code installed, with usage data under `~/.claude/`

---

## Build & run

```bash
swift build            # build
swift test             # run the test suite (Swift Testing)
swift run CCTTApp      # launch the menu-bar app
```

### `./run.sh` (recommended for live limits)

If you enable **live limits**, use `./run.sh` instead of `swift run`:

```bash
./run.sh          # debug
./run.sh release  # release
```

`run.sh` builds, then code-signs the binary with a **stable** designated requirement.
Live limits read Claude Code's OAuth token from the Keychain, and macOS ties the
"Always Allow" grant to the app's code signature. Ad-hoc signatures (what plain
`swift build` / `swift run` produce) change on every rebuild, so macOS would re-prompt
each launch. Stable signing means you click **Always Allow** once. *(You'll need to set
your own signing identity in `run.sh`.)*

---

## Configuration

CCTT is user-configurable through its Settings window (`⌘,`):

- **Plan** — auto-detected, with a manual override and API budget / manual caps.
- **Live limits** — opt in or out; degrades gracefully to estimates on any failure.
- **Alerts** — usage thresholds.
- **Display** — show/hide tabs, popover sections, glance content; switch units ($ ⇄ tokens).
- **Data** — data-source paths and diagnostics.

---

## Testing

Development is test-driven (188 tests, Swift Testing). The pure core is exercised with
fixture `.jsonl` and `~/.claude.json` files; an injected clock and a stubbed
`LiveLimitProvider` keep `UsageStore` / `LimitEngine` deterministic. UI is verified via
SwiftUI previews.

```bash
swift test --filter <SuiteOrName>   # run a subset
```

---

## Design principles

- **Data provenance is always explicit.** Never mix measured and estimated numbers
  ambiguously.
- **Never lie or crash on bad input.** Malformed lines are skipped and counted; missing
  data yields a friendly empty state; a live-limit failure auto-degrades to estimates
  with a badge flip.
- **Read-only.** CCTT never writes to `~/.claude/` or influences Claude Code.
- **Configurable.** Tabs, sections, glance content, and units are all show/hide-able.

---

## Roadmap

CCTT is under active development. Completed work spans the data pipeline, plan detection
and limit engine, the detail UI, and live limits / credits / alerts / settings /
onboarding.

Not yet done: packaging as a distributable `.app` (notarized, drag-to-Applications).

---

## Project layout

```text
Sources/
  CCTTCore/     Pure, file-driven core: ingest, aggregate, plan/limit engine
  CCTTApp/      SwiftUI menu-bar app: glance, popover, dashboard, settings
Tests/
  CCTTCoreTests/
run.sh          Build + stable code-sign + launch
```

---

## License

[MIT](LICENSE) © 2026 Jesper Mol
