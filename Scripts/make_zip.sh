#!/usr/bin/env bash
# Zip NarrationBooth.app for download: dist/NarrationBooth-<version>.zip. Run Scripts/package_app.sh first.
# Why a ZIP and not a DMG: recent macOS turns a DMG with an app into an "Install this app?" dialog that refuses any app
# Apple hasn't notarized ("This Mac can't verify this app, so it wasn't installed"). A ZIP is just unzipped and dragged
# into Applications, and the one-time Privacy & Security → Open Anyway step works as usual.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source version.env
[[ -d NarrationBooth.app ]] || { echo "run Scripts/package_app.sh first" >&2; exit 1; }
mkdir -p dist
ZIP="dist/NarrationBooth-${MARKETING_VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent NarrationBooth.app "$ZIP"
echo "ZIP: $ZIP"
