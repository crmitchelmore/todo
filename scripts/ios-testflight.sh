#!/usr/bin/env bash
# Build, archive and upload the Capture iOS app to TestFlight.
#
# Uses Xcode "cloud signing": automatic signing + -allowProvisioningUpdates with an
# App Store Connect API key. Xcode creates/uses a cloud-managed distribution certificate
# and provisioning profiles for the bundle IDs automatically — no p12/profile wrangling.
#
# Prereqsuisites:
#   - Xcode + an installed iOS platform/runtime.
#   - App Store Connect API key (.p8) on disk.
#   - The app record must already exist in App Store Connect (run scripts/appstore-bootstrap.py once).
#
# Required env:
#   APP_STORE_CONNECT_ISSUER_ID   App Store Connect API issuer UUID.
# Optional env (sensible defaults for this machine):
#   APP_STORE_CONNECT_KEY_ID      Default: Y6C8R5DA75
#   APP_STORE_CONNECT_KEY_PATH    Default: ~/.private_keys/AuthKey_<KEY_ID>.p8
#   APPLE_TEAM_ID                 Default: 8X4ZN58TYH
#   VERSION                       Default: contents of ./VERSION
#   BUILD_NUMBER                  Default: unix timestamp
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR="$ROOT_DIR/clients/apps"

APP_STORE_CONNECT_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-Y6C8R5DA75}"
APP_STORE_CONNECT_KEY_PATH="${APP_STORE_CONNECT_KEY_PATH:-$HOME/.private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-8X4ZN58TYH}"
VERSION="${VERSION:-$(cat "$ROOT_DIR/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%s)}"

: "${APP_STORE_CONNECT_ISSUER_ID:?Set APP_STORE_CONNECT_ISSUER_ID (App Store Connect API issuer UUID)}"
[ -f "$APP_STORE_CONNECT_KEY_PATH" ] || { echo "API key not found: $APP_STORE_CONNECT_KEY_PATH" >&2; exit 1; }

BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/CaptureiOS.xcarchive"
EXPORT_PATH="$BUILD_DIR/CaptureiOS-export"
mkdir -p "$BUILD_DIR"

echo "==> Generating Xcode project (XcodeGen)"
( cd "$APPS_DIR" && GIT_CONFIG_COUNT=0 xcodegen generate )

echo "==> Archiving CaptureiOS ($VERSION build $BUILD_NUMBER)"
GIT_CONFIG_COUNT=0 xcodebuild archive \
  -project "$APPS_DIR/Capture.xcodeproj" \
  -scheme CaptureiOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>upload</string>
</dict>
</plist>
PLIST

echo "==> Exporting + uploading to App Store Connect"
rm -rf "$EXPORT_PATH"
GIT_CONFIG_COUNT=0 xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"

echo "✅ Uploaded. Build will appear in TestFlight after Apple processing (5-30 min)."
