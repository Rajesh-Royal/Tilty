#!/usr/bin/env bash
# Renders scripts/og/og.html into docs/og.png (1200x630 share image)
# and docs/apple-touch-icon.png (180x180) from Resources/AppIcon.svg.
# Needs Google Chrome and an internet connection for the web font.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

"$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --virtual-time-budget=5000 --window-size=1200,630 \
  --screenshot="$PWD/docs/og.png" "file://$PWD/scripts/og/og.html" >/dev/null 2>&1
echo "Wrote docs/og.png"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/icon.html" <<HTML
<html><body style="margin:0;background:#15142a"><img src="file://$PWD/docs/icon.svg" style="width:180px;height:180px;display:block"></body></html>
HTML
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --window-size=180,180 --screenshot="$PWD/docs/apple-touch-icon.png" "file://$WORK/icon.html" >/dev/null 2>&1
echo "Wrote docs/apple-touch-icon.png"
