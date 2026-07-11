#!/usr/bin/env bash
# Regenerate the macOS app icon from the source logo.
#   packaging/icon/make_icon.sh
#
# Produces (committed, so releases don't depend on Python/PIL at package time):
#   packaging/icon/AppIcon.icns          — Finder/Get-Info bundle icon (CFBundleIconFile)
#   packaging/icon/AppIcon-1024.png       — flattened 1024 tile for the runtime Dock icon
#   Sources/CCTTApp/Resources/AppIcon-1024.png (copy, loaded via Bundle.module)
#
# macOS does NOT auto-round app icons: the squircle + safe-area padding are baked
# into the art here, following the Big Sur grid (824px body centered on a 1024
# canvas, 100px margin, corner radius ≈ 0.2237×824 ≈ 184).
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"

SRC="CCTT-logo-source.png"
[ -f "$SRC" ] || { echo "missing $SRC"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "▶ Rendering 1024 squircle tile…"
python3 - "$SRC" "$WORK/icon_1024.png" <<'PY'
import sys
from PIL import Image, ImageDraw

src_path, out_path = sys.argv[1], sys.argv[2]
CANVAS = 1024
BODY   = 824                 # Big Sur icon-grid body size
MARGIN = (CANVAS - BODY) // 2
RADIUS = round(0.2237 * BODY)

src = Image.open(src_path).convert("RGBA")
# The source is a white square with the art centered; scale it to the body size.
tile = src.resize((BODY, BODY), Image.LANCZOS)

# Flatten the tile onto solid white so any source anti-aliasing edges stay white.
white = Image.new("RGBA", (BODY, BODY), (255, 255, 255, 255))
white.paste(tile, (0, 0), tile)
tile = white

# Rounded-rectangle (squircle approximation) alpha mask for the body.
mask = Image.new("L", (BODY, BODY), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, BODY - 1, BODY - 1], radius=RADIUS, fill=255)

canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
canvas.paste(tile, (MARGIN, MARGIN), mask)
canvas.save(out_path)
print(f"  body={BODY} margin={MARGIN} radius={RADIUS}")
PY

echo "▶ Emitting iconset sizes…"
gen() { # size filename
  sips -z "$1" "$1" "$WORK/icon_1024.png" --out "$ICONSET/$2" >/dev/null
}
gen 16    icon_16x16.png
gen 32    icon_16x16@2x.png
gen 32    icon_32x32.png
gen 64    icon_32x32@2x.png
gen 128   icon_128x128.png
gen 256   icon_128x128@2x.png
gen 256   icon_256x256.png
gen 512   icon_256x256@2x.png
gen 512   icon_512x512.png
cp "$WORK/icon_1024.png" "$ICONSET/icon_512x512@2x.png"

echo "▶ Building AppIcon.icns…"
iconutil -c icns "$ICONSET" -o AppIcon.icns

echo "▶ Writing runtime Dock PNG…"
cp "$WORK/icon_1024.png" AppIcon-1024.png
cp "$WORK/icon_1024.png" "$ROOT/Sources/CCTTApp/Resources/AppIcon-1024.png"

echo "▶ Regenerating in-app Brand assets (CCTTLogo = full, CCTTMark = mascot-only)…"
python3 - "$SRC" "$ROOT/Sources/CCTTApp/Resources" <<'PY'
import sys
from PIL import Image

src_path, res_dir = sys.argv[1], sys.argv[2]
src = Image.open(src_path).convert("RGBA")

def content_bbox(img, rows=None, thresh=235):
    """Bounding box of non-white ink, optionally within a row band."""
    px = img.load(); w, h = img.size
    y0, y1 = (rows if rows else (0, h))
    minx = miny = 10**9; maxx = maxy = -1
    for y in range(y0, y1):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 10 and (r < thresh or g < thresh or b < thresh):
                minx = min(minx, x); maxx = max(maxx, x)
                miny = min(miny, y); maxy = max(maxy, y)
    return (minx, miny, maxx + 1, maxy + 1)

def squared_on_white(crop, out_size, pad_frac=0.06):
    """Center `crop` on a white square with a little padding, at out_size."""
    cw, ch = crop.size
    side = int(max(cw, ch) * (1 + 2 * pad_frac))
    tile = Image.new("RGBA", (side, side), (255, 255, 255, 255))
    tile.paste(crop, ((side - cw) // 2, (side - ch) // 2), crop)
    return tile.resize((out_size, out_size), Image.LANCZOS)

# Full logo (parrot + CCTT wordmark): trim outer margin, re-square, 512.
full = squared_on_white(src.crop(content_bbox(src)), 512, pad_frac=0.08)
full.save(f"{res_dir}/CCTTLogo.png")

# Mascot-only mark: the wordmark sits below a white gap; crop the parrot cluster
# (everything above the gap) and re-square at 256.
w, h = src.size
px = src.load()
def row_has_ink(y, thresh=235):
    return any(px[x, y][3] > 10 and min(px[x, y][:3]) < thresh for x in range(w))
gap_start = next((y for y in range(h // 3, h) if not row_has_ink(y)
                  and not row_has_ink(y + 1) and not row_has_ink(y + 2)), h)
parrot = src.crop(content_bbox(src, rows=(0, gap_start)))
squared_on_white(parrot, 256, pad_frac=0.10).save(f"{res_dir}/CCTTMark.png")
print(f"  CCTTLogo 512, CCTTMark 256 (parrot rows 0..{gap_start})")
PY

echo "✅ Wrote AppIcon.icns, AppIcon-1024.png, and refreshed CCTTLogo.png / CCTTMark.png"
