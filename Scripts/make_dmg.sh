#!/usr/bin/env bash
# Wrap NarrationBooth.app in a drag-to-install disk image: dist/NarrationBooth-<version>.dmg
# (the window shows the app next to an Applications shortcut). Run Scripts/package_app.sh first.
# If a "Developer ID Application" identity and a notarytool keychain profile (NOTARY_PROFILE, default "narrationbooth")
# exist, the DMG is signed, notarized and stapled so it opens without any Gatekeeper warning.
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

DEVID=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
PROFILE=${NOTARY_PROFILE:-narrationbooth}
if [[ -n "$DEVID" ]]; then
  codesign --force --timestamp --sign "$DEVID" "$DMG"
  if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "notarized: $DMG"
  else
    echo "signed but NOT notarized (no notarytool profile \"$PROFILE\"; create it with: xcrun notarytool store-credentials $PROFILE)"
  fi
else
  echo "not notarized: no Developer ID Application certificate (first launch needs right-click → Open)"
fi
echo "DMG: $DMG"
