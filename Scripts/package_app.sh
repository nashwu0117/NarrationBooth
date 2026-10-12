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
cp -R "$ROOT/Localizations" "$APP/Contents/Resources/Localizations"      # UI translations (see Localizations/README.md)
# empty .lproj folders tell macOS which languages the app speaks, so its own menus (Quit, Edit, Window…) follow along
for l in en zh-Hant zh-Hans ja ko es fr de; do mkdir -p "$APP/Contents/Resources/$l.lproj"; done

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
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>zh-Hant</string><string>zh-Hans</string><string>ja</string><string>ko</string><string>es</string><string>fr</string><string>de</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>NarrationBooth records your voice with the microphone.</string>
    <key>NSCameraUsageDescription</key><string>NarrationBooth records video with the camera in Camera mode.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Narration Script</string>
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

# Signing:
# - RELEASE=1 (Scripts/release.sh): ad hoc. Builds for download carry no personal certificate; people allow the app once
#   under System Settings → Privacy & Security → Open Anyway, like most apps distributed on GitHub.
# - local builds: APP_IDENTITY if set, else an "Apple Development" identity from the keychain when there is one (a stable
#   signature means macOS keeps the mic/camera permission across rebuilds), else ad hoc.
ENT="$ROOT/Scripts/NarrationBooth.entitlements"
if [[ "${RELEASE:-0}" == "1" ]]; then
  APP_IDENTITY=""
elif [[ -z "${APP_IDENTITY:-}" ]]; then
  APP_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)
fi
if [[ -n "$APP_IDENTITY" ]]; then
  codesign --force --entitlements "$ENT" --sign "$APP_IDENTITY" "$APP"
else
  codesign --force --entitlements "$ENT" --sign - --identifier com.nashwu.narrationbooth "$APP"
fi
codesign --verify "$APP" && echo "OK: $APP  (signed: ${APP_IDENTITY:-ad hoc})"
if [[ "${INSTALL:-0}" == "1" ]]; then
  rm -rf "/Applications/NarrationBooth.app"
  cp -R "$APP" /Applications/ && echo "installed: /Applications/NarrationBooth.app"
fi
