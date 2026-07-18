#!/bin/bash
set -euo pipefail

# build_dmg.sh — Release build + drag-to-Applications DMG for Vibe Buddy.
#
# Plan-B distribution (no paid Apple Developer account on the team): the app
# is signed with the Apple Development certificate — NOT notarized. On a Mac
# that didn't build it, first launch needs right-click > Open. The live demo
# runs on the team's own Macs, so this only affects the download story.
#
# Usage:  bash app/scripts/build_dmg.sh
# Output: dist/VibeBuddy.dmg

cd "$(dirname "$0")/../.."

DERIVED=/tmp/dd-release
STAGING=/tmp/vibebuddy-dmg-staging
mkdir -p dist

echo "== Building Release =="
xcodebuild -project app/leanring-buddy.xcodeproj -scheme leanring-buddy \
  -configuration Release -derivedDataPath "$DERIVED" build \
  -allowProvisioningUpdates | tail -2

APP="$DERIVED/Build/Products/Release/VibeBuddy.app"
test -d "$APP" || { echo "app not found at $APP"; exit 1; }

echo "== Staging DMG =="
rm -rf "$STAGING" && mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/Vibe Buddy.app"
ln -s /Applications "$STAGING/Applications"

echo "== Creating dist/VibeBuddy.dmg =="
rm -f dist/VibeBuddy.dmg
hdiutil create -volname "Vibe Buddy" -srcfolder "$STAGING" -ov -format UDZO \
  -quiet dist/VibeBuddy.dmg

echo "== Done =="
ls -lh dist/VibeBuddy.dmg
codesign -dv "$STAGING/Vibe Buddy.app" 2>&1 | grep -E "Authority|TeamIdentifier" | head -2 || true
