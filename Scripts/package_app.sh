#!/usr/bin/env bash
# Build NarrationBooth and wrap it as a double-clickable .app (ad-hoc signed, local use).
# Usage: Scripts/package_app.sh   -> ./NarrationBooth.app   (INSTALL=1 also copies it to /Applications)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source version.env
EXE=NarrationBooth
APP="$ROOT/NarrationBooth.app"

ARCH=$(uname -m)
swift build -c release --arch "$ARCH"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN=$(swift build -c release --arch "$ARCH" --show-bin-path)
cp "$BIN/$EXE" "$APP/Contents/MacOS/$EXE"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/Icon.icns"   # icon source: Scripts/draw_icon.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NarrationBooth</string>
    <key>CFBundleDisplayName</key><string>NarrationBooth</string>
    <key>CFBundleIdentifier</key><string>com.nashwu.narrationbooth</string>
    <key>CFBundleExecutable</key><string>${EXE}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>NarrationBooth records your voice with the microphone.</string>
    <key>NSCameraUsageDescription</key><string>NarrationBooth records video with the camera in Camera mode.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>錄音稿</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>public.plain-text</string><string>net.daringfireball.markdown</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

xattr -cr "$APP"

# Signing: APP_IDENTITY if set, else the best identity in the keychain:
#   "Developer ID Application" (hardened runtime, notarizable) > "Apple Development" (stable local identity, so macOS
#   keeps the mic/camera permission across rebuilds) > ad hoc.
if [[ -z "${APP_IDENTITY:-}" ]]; then
  APP_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
  [[ -z "$APP_IDENTITY" ]] && APP_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)
fi
ENT="$ROOT/Scripts/NarrationBooth.entitlements"
if [[ "$APP_IDENTITY" == Developer\ ID* ]]; then
  codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$APP_IDENTITY" "$APP"
elif [[ -n "$APP_IDENTITY" ]]; then
  codesign --force --entitlements "$ENT" --sign "$APP_IDENTITY" "$APP"
else
  codesign --force --sign - --identifier com.nashwu.narrationbooth "$APP"
fi
codesign --verify "$APP" && echo "OK: $APP  (signed: ${APP_IDENTITY:-ad hoc})"
if [[ "${INSTALL:-0}" == "1" ]]; then
  rm -rf "/Applications/NarrationBooth.app"
  cp -R "$APP" /Applications/ && echo "installed: /Applications/NarrationBooth.app"
fi
