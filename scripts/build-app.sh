#!/usr/bin/env bash
# Builds Tilty.app into ./build.
#
# Usage:
#   scripts/build-app.sh            build a release app
#   scripts/build-app.sh --install  also copy it to /Applications and open it
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="app.tilty.Tilty"
APP="build/Tilty.app"
VERSION="0.1.0"

# Prefer full Xcode when Command Line Tools is the active developer directory.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Tilty"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tilty"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Tilty</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>Tilty</string>
  <key>CFBundleDisplayName</key><string>Tilty</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. macOS ties the Accessibility grant to this signature,
# so a rebuild needs the grant again (see README).
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Tilty 2>/dev/null || true
  rm -rf /Applications/Tilty.app
  cp -R "$APP" /Applications/Tilty.app
  # Clear the old grant, which no longer matches the new signature.
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  open /Applications/Tilty.app
  echo "Installed to /Applications/Tilty.app"
fi
