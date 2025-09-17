#!/bin/bash
# sign_notarize.sh - Build, sign, notarize, and package DiskSpaceSwiftUI as a DMG
# Usage:
#   CERT_NAME="Developer ID Application: Your Name (TEAMID)" \
#   TEAM_ID="YOURTEAMID" \
#   BUNDLE_ID="com.teddy.DiskSpaceSwiftUI" \
#   KEYCHAIN_PROFILE="NotaryProfile" \
#   ./sign_notarize.sh
#
# Or with Apple ID auth:
#   APPLE_ID="you@apple.com" TEAM_ID="YOURTEAMID" APP_SPECIFIC_PW="xxxx-xxxx-xxxx-xxxx" ./sign_notarize.sh

set -euo pipefail

APP_DIR="$HOME/Applications/DiskSpaceSwiftUI.app"
PROJECT_DIR="$HOME/DiskSpaceSwiftUI"
DMG_OUT="$HOME/Desktop/DiskSpace.dmg"

CERT_NAME=${CERT_NAME:-}
TEAM_ID=${TEAM_ID:-}
BUNDLE_ID=${BUNDLE_ID:-com.teddy.DiskSpaceSwiftUI}
KEYCHAIN_PROFILE=${KEYCHAIN_PROFILE:-}
APPLE_ID=${APPLE_ID:-}
APP_SPECIFIC_PW=${APP_SPECIFIC_PW:-}

if [ -z "$CERT_NAME" ] || [ -z "$TEAM_ID" ]; then
  echo "ERROR: CERT_NAME and TEAM_ID must be set." >&2
  exit 1
fi

# 1) Build the app
cd "$PROJECT_DIR"
swift build -c release
./build-app.sh

# 2) Update bundle identifier if needed
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist" || true

# 3) Codesign (deep, hardened runtime)
codesign --force --deep --timestamp --options runtime --sign "$CERT_NAME" "$APP_DIR"

# 4) Verify signature
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl -a -vv "$APP_DIR" || true

# 5) Create DMG
hdiutil create -volname "DiskSpace" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_OUT"

# 6) Notarize (prefer keychain profile; fallback to Apple ID)
if [ -n "$KEYCHAIN_PROFILE" ]; then
  xcrun notarytool submit "$DMG_OUT" --keychain-profile "$KEYCHAIN_PROFILE" --team-id "$TEAM_ID" --wait
else
  if [ -z "$APPLE_ID" ] || [ -z "$APP_SPECIFIC_PW" ]; then
    echo "WARNING: Notarization skipped (no KEYCHAIN_PROFILE or APPLE_ID/APP_SPECIFIC_PW)." >&2
    exit 0
  fi
  xcrun notarytool submit "$DMG_OUT" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_SPECIFIC_PW" --wait
fi

# 7) Staple
xcrun stapler staple "$DMG_OUT"

echo "SUCCESS: Signed, notarized DMG at $DMG_OUT"