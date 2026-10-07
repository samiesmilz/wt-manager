#!/usr/bin/env bash
# Assembles wt-manager.app.
#
# The bundle carries its own engine. A menu bar app that shells out to whatever
# `wt-manager` happens to be on PATH would change behaviour when the checkout moves,
# and a login item starts with almost no PATH at all -- so the Python lives in
# Resources and is addressed absolutely.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$(cd "$ROOT/.." && pwd)"          # the wt-manager/ directory holding wtmanager.py
CONFIG="${CONFIG:-release}"
APP="$ROOT/wt-manager.app"
BUNDLE_ID="com.samiesmilz.wtmanager"
VERSION="$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$ENGINE/wtmanager.py" | head -1)"
VERSION="${VERSION:-0.0.0}"

echo "==> building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"
# The SwiftPM target is WTManager; the bundle executable is wt-manager.
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/WTManager"
[ -f "$BIN" ] || { echo "binary not found at $BIN" >&2; exit 1; }

echo "==> assembling $APP"
[ -e "$APP" ] && rm -r "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/engine"
cp "$BIN" "$APP/Contents/MacOS/wt-manager"

echo "==> baking the character"
python3 "$ENGINE/mascot.py" "$APP/Contents/Resources/mascot.json" >/dev/null

echo "==> embedding the engine"
for f in wtmanager.py mascot.py; do
  cp "$ENGINE/$f" "$APP/Contents/Resources/engine/$f"
done
chmod +x "$APP/Contents/Resources/engine/wtmanager.py"

echo "==> generating icon"
if swift run -c "$CONFIG" --package-path "$ROOT" MakeIcon \
      "$APP/Contents/Resources/mascot.json" "$ROOT/.build" >/dev/null 2>&1 \
   && iconutil -c icns "$ROOT/.build/AppIcon.iconset" \
        -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  ICON_KEY='<key>CFBundleIconFile</key><string>AppIcon</string>'
else
  # Worth shouting about: with no icon key the bundle declares no icon at all,
  # and what gets shown is whatever the icon cache still holds -- which looks
  # exactly like the icon simply not having changed.
  echo "    !! icon generation FAILED - app will ship with no icon of its own" >&2
  ICON_KEY=''
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>wt-manager</string>
  <key>CFBundleDisplayName</key><string>wt-manager</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>wt-manager</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- Agent app: a status item only, no Dock icon and no menu of its own. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  $ICON_KEY
</dict>
</plist>
PLIST

echo "==> ad-hoc signing"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
  || echo "    !! codesign failed - macOS may refuse to launch it" >&2

echo "==> $APP ($VERSION)"
