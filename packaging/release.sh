#!/usr/bin/env bash
# Notarize, staple, zip, EdDSA-sign, and append an appcast entry.
#   packaging/release.sh <version>
# Prereqs: build/CCTT.app exists (run package_app.sh first);
#          notarytool keychain profile "CCTT-notary"; Sparkle sign_update on PATH
#          or discoverable in .build artifacts.
set -euo pipefail

VERSION="${1:?usage: release.sh <version>}"
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/CCTT.app"
ZIP="$ROOT/build/CCTT-$VERSION.zip"
[ -d "$APP" ] || { echo "Missing $APP — run package_app.sh $VERSION first"; exit 1; }

echo "▶ Notarizing…"
ditto -c -k --keepParent "$APP" "$ZIP"
NOTARY_JSON="$(xcrun notarytool submit "$ZIP" --keychain-profile "CCTT-notary" --wait --output-format json)"
echo "$NOTARY_JSON"
NOTARY_STATUS="$(printf '%s' "$NOTARY_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status",""))')"
if [ "$NOTARY_STATUS" != "Accepted" ]; then
  echo "❌ Notarization not accepted (status: ${NOTARY_STATUS:-unknown}). Fetching log…"
  SUBMISSION_ID="$(printf '%s' "$NOTARY_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))')"
  [ -n "$SUBMISSION_ID" ] && xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "CCTT-notary" || true
  exit 1
fi

echo "▶ Stapling…"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip the stapled app

echo "▶ EdDSA-signing the update…"
SIGN_UPDATE="$(find "$ROOT/.build" -name 'sign_update' -type f | head -1)"
[ -n "$SIGN_UPDATE" ] || { echo "sign_update tool not found in .build"; exit 1; }
SIG_LINE="$("$SIGN_UPDATE" "$ZIP")"   # prints: sparkle:edSignature="…" length="…"
PUBDATE="$(date -u +'%a, %d %b %Y %H:%M:%S +0000')"
DL="https://github.com/Arc86/CCTT/releases/download/v$VERSION/CCTT-$VERSION.zip"

# Inline release notes (shown in Sparkle's update dialog) from an optional
# per-version HTML file. Without it, Sparkle shows the bare "new version" dialog.
NOTES_FILE="$ROOT/packaging/release-notes/$VERSION.html"
DESC=""
if [ -f "$NOTES_FILE" ]; then
  DESC="
      <description><![CDATA[
$(cat "$NOTES_FILE")
      ]]></description>"
else
  echo "⚠ No release notes at packaging/release-notes/$VERSION.html — dialog will have no notes."
fi

echo "▶ Appending appcast entry…"
ITEM="    <item>
      <title>Version $VERSION</title>$DESC
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <pubDate>$PUBDATE</pubDate>
      <enclosure url=\"$DL\" $SIG_LINE type=\"application/octet-stream\" />
    </item>"
# Insert before the closing </channel>
python3 - "$ROOT/appcast.xml" "$ITEM" "$VERSION" <<'PY'
import sys
path, item, version = sys.argv[1], sys.argv[2], sys.argv[3]
xml = open(path).read()
if f"<sparkle:version>{version}</sparkle:version>" in xml:
    sys.exit(f"appcast.xml already has an entry for version {version}; aborting to avoid a duplicate")
anchor = "  </channel>"
if anchor not in xml:
    sys.exit("could not find the </channel> anchor in appcast.xml; aborting (the entry was NOT added)")
xml = xml.replace(anchor, item + "\n" + anchor, 1)
open(path, "w").write(xml)
PY

echo "✅ Release prepared. Next:"
echo "   gh release create v$VERSION \"$ZIP\" --title \"CCTT v$VERSION\" --notes \"…\""
echo "   git add appcast.xml && git commit -m \"release: v$VERSION\" && git push"
