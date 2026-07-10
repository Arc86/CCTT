#!/usr/bin/env bash
# Notarize, staple, zip, EdDSA-sign, and append an appcast entry.
#   packaging/release.sh <version>
# Prereqs: build/CCTTApp.app exists (run package_app.sh first);
#          notarytool keychain profile "CCTT-notary"; Sparkle sign_update on PATH
#          or discoverable in .build artifacts.
set -euo pipefail

VERSION="${1:?usage: release.sh <version>}"
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/CCTTApp.app"
ZIP="$ROOT/build/CCTTApp-$VERSION.zip"
[ -d "$APP" ] || { echo "Missing $APP — run package_app.sh $VERSION first"; exit 1; }

echo "▶ Notarizing…"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "CCTT-notary" --wait

echo "▶ Stapling…"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip the stapled app

echo "▶ EdDSA-signing the update…"
SIGN_UPDATE="$(find "$ROOT/.build" -name 'sign_update' -type f | head -1)"
[ -n "$SIGN_UPDATE" ] || { echo "sign_update tool not found in .build"; exit 1; }
SIG_LINE="$("$SIGN_UPDATE" "$ZIP")"   # prints: sparkle:edSignature="…" length="…"
LEN="$(stat -f%z "$ZIP")"
PUBDATE="$(date -u +'%a, %d %b %Y %H:%M:%S +0000')"
DL="https://github.com/Arc86/CCTT/releases/download/v$VERSION/CCTTApp-$VERSION.zip"

echo "▶ Appending appcast entry…"
ITEM="    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <pubDate>$PUBDATE</pubDate>
      <enclosure url=\"$DL\" $SIG_LINE type=\"application/octet-stream\" />
    </item>"
# Insert before the closing </channel>
python3 - "$ROOT/packaging/appcast.xml" "$ITEM" <<'PY'
import sys
path, item = sys.argv[1], sys.argv[2]
xml = open(path).read()
xml = xml.replace("  </channel>", item + "\n  </channel>", 1)
open(path, "w").write(xml)
PY

echo "✅ Release prepared. Next:"
echo "   gh release create v$VERSION \"$ZIP\" --title \"CCTT v$VERSION\" --notes \"…\""
echo "   git add packaging/appcast.xml && git commit -m \"release: v$VERSION\" && git push"
