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
# Sign nested helpers first, then the framework, then the app.
codesign --force --options runtime --sign "$IDENTITY" \
  "$FW/Versions/B/XPCServices/Installer.xpc" \
  "$FW/Versions/B/XPCServices/Downloader.xpc" \
  "$FW/Versions/B/Autoupdate" \
  "$FW/Versions/B/Updater.app" 2>/dev/null || true
codesign --force --options runtime --sign "$IDENTITY" "$FW"
codesign --force --options runtime \
  --identifier "com.jespermol.CCTT" \
  --sign "$IDENTITY" \
  "$APP"

echo "▶ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "✅ Built $APP (v$VERSION)"
