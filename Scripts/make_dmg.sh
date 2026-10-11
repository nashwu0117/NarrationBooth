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
rm -f "$DMG"
hdiutil create -volname "NarrationBooth ${MARKETING_VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "DMG: $DMG"
