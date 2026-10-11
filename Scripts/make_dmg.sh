#!/usr/bin/env bash
# Wrap NarrationBooth.app in a drag-to-install disk image: dist/NarrationBooth-<version>.dmg
# (the window shows the app next to an Applications shortcut). Run Scripts/package_app.sh first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source version.env
APP="$ROOT/NarrationBooth.app"
[[ -d "$APP" ]] || { echo "run Scripts/package_app.sh first" >&2; exit 1; }
mkdir -p dist
DMG="dist/NarrationBooth-${MARKETING_VERSION}.dmg"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"   # the mounted disk shows the app icon
rm -f "$DMG"
RW="$STAGE.rw.dmg"
hdiutil create -volname "NarrationBooth ${MARKETING_VERSION}" -srcfolder "$STAGE" -ov -format UDRW "$RW" >/dev/null
MNT=$(hdiutil attach -nobrowse -readwrite "$RW" | tail -1 | cut -f3-)
SETFILE=$(xcrun -f SetFile 2>/dev/null || echo /usr/bin/SetFile)
"$SETFILE" -a C "$MNT" 2>/dev/null || true                     # tell Finder the volume has a custom icon
hdiutil detach -quiet "$MNT"
hdiutil convert "$RW" -format UDZO -o "$DMG" >/dev/null
rm -rf "$STAGE" "$RW"

echo "DMG: $DMG"
