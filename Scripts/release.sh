#!/usr/bin/env bash
# Publish a new version: bump version.env, build, make the DMG, tag, push, and create the GitHub release with the DMG.
# The app's update checker (Updater.swift) looks at the latest GitHub release, so users get told about it.
# Usage: Scripts/release.sh 1.1.0 "What changed (one line or more)"
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=${1:?usage: Scripts/release.sh <version> "<notes>"}
NOTES=${2:-"NarrationBooth $VERSION"}
source version.env
BUILD=$((BUILD_NUMBER + 1))
printf 'MARKETING_VERSION=%s\nBUILD_NUMBER=%s\n' "$VERSION" "$BUILD" > version.env
Scripts/package_app.sh
Scripts/make_dmg.sh
git add version.env
git commit -m "Release $VERSION" >/dev/null || true
git tag "v$VERSION"
git push origin HEAD "v$VERSION"
gh release create "v$VERSION" "dist/NarrationBooth-$VERSION.dmg" --title "NarrationBooth $VERSION" --notes "$NOTES"
