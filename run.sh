#!/usr/bin/env bash
# Build, stably code-sign, and launch CCTTApp.
#
# Why the codesign step: the Keychain "Always Allow" grant for reading Claude
# Code's OAuth credentials is tied to the app's code-signing designated
# requirement. An ad-hoc signature (what `swift build`/`swift run` produce)
# pins that requirement to the binary's cdhash, which changes on every rebuild
# — so macOS re-prompts every launch. Signing with a real Developer ID cert and
# a stable identifier makes the requirement cdhash-independent, so the grant
# persists across rebuilds. Click "Always Allow" once and you're done.
set -euo pipefail

CONFIG="${1:-debug}"                       # ./run.sh [debug|release]
IDENTITY="Developer ID Application: Jesper Mol (9WFDLY652Y)"
BUNDLE_ID="com.jespermol.CCTT"

cd "$(dirname "$0")"

echo "▶ Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/CCTTApp"

echo "▶ Signing with stable identity…"
codesign --force \
  --sign "$IDENTITY" \
  --identifier "$BUNDLE_ID" \
  "$BIN"

echo "▶ Launching…"
exec "$BIN"
