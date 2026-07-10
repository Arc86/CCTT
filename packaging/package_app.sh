#!/usr/bin/env bash
# Assemble a signed CCTTApp.app from the SwiftPM release build.
#   packaging/package_app.sh <version>
# Requires env: CCTT_ED_PUBKEY (Sparkle public EdDSA key, from `generate_keys`).
set -euo pipefail

VERSION="${1:?usage: package_app.sh <version>}"
IDENTITY="Developer ID Application: Jesper Mol (9WFDLY652Y)"
: "${CCTT_ED_PUBKEY:?set CCTT_ED_PUBKEY to the Sparkle public key}"

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/CCTTApp.app"
CONTENTS="$APP/Contents"

echo "▶ Building release…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▶ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

# Executable
cp "$BIN_DIR/CCTTApp" "$CONTENTS/MacOS/CCTTApp"

# SwiftPM resource bundle (Brand assets loaded via Bundle.module)
cp -R "$BIN_DIR/CCTT_CCTTApp.bundle" "$CONTENTS/Resources/"

# Info.plist (substitute version + public key)
sed -e "s/__VERSION__/$VERSION/g" \
    -e "s|__PUBKEY__|$CCTT_ED_PUBKEY|g" \
    "$ROOT/packaging/Info.plist.template" > "$CONTENTS/Info.plist"

# Embed Sparkle.framework from the resolved SPM artifacts
SPARKLE_FW="$(find "$ROOT/.build" -name 'Sparkle.framework' -type d -path '*artifacts*' | head -1)"
if [ -z "$SPARKLE_FW" ]; then
  SPARKLE_FW="$(find "$ROOT/.build" -name 'Sparkle.framework' -type d | head -1)"
fi
[ -n "$SPARKLE_FW" ] || { echo "Sparkle.framework not found — run 'swift build' first"; exit 1; }
cp -R "$SPARKLE_FW" "$CONTENTS/Frameworks/"

echo "▶ Deep code-signing (inside-out, hardened runtime)…"
FW="$CONTENTS/Frameworks/Sparkle.framework"
# Re-sign every embedded Sparkle helper with OUR identity, inside-out, BEFORE
# the framework and app. Use Versions/Current (the symlink Sparkle maintains)
# so this survives a Sparkle version-letter bump. --deep on the bundles/xpc
# re-signs their nested code with our team too (required for notarization; the
# later --verify --strict would otherwise pass a Sparkle-team signature). Each
# helper that EXISTS must sign successfully — no error swallowing, so a
# mis-sign can't slip through.
for rel in \
  "Versions/Current/XPCServices/Installer.xpc" \
  "Versions/Current/XPCServices/Downloader.xpc" \
  "Versions/Current/Autoupdate" \
  "Versions/Current/Updater.app"; do
  helper="$FW/$rel"
  if [ -e "$helper" ]; then
    codesign --force --options runtime --deep --sign "$IDENTITY" "$helper"
  else
    echo "⚠ Sparkle helper not found (skipped): $rel"
  fi
done
codesign --force --options runtime --sign "$IDENTITY" "$FW"
codesign --force --options runtime \
  --identifier "com.jespermol.CCTT" \
  --sign "$IDENTITY" \
  "$APP"

echo "▶ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "✅ Built $APP (v$VERSION)"
