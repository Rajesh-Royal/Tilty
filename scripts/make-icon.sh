#!/usr/bin/env bash
# Renders Resources/AppIcon.svg into Resources/AppIcon.icns.
# Needs Google Chrome (for SVG rendering) plus the built-in sips and iconutil.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/icon.html" <<HTML
<html><body style="margin:0;background:transparent">$(cat Resources/AppIcon.svg)</body></html>
HTML
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --window-size=1024,1024 --screenshot="$WORK/icon_1024.png" "file://$WORK/icon.html" >/dev/null 2>&1

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
