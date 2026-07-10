#!/usr/bin/env bash
# Build, archive and upload the Capture iOS app to TestFlight.
#
# Uses manual signing with reusable Apple Distribution certificates and App Store
# provisioning profiles installed by CI/local setup. Do not pass -allowProvisioningUpdates:
# that allows Xcode to create/repair Apple signing assets from an ephemeral runner.
#
# Prereqsuisites:
#   - Xcode + an installed iOS platform/runtime.
#   - App Store Connect API key (.p8) on disk.
#   - The app record must already exist in App Store Connect (run scripts/appstore-bootstrap.py once).
#
# Required env:
#   APP_STORE_CONNECT_ISSUER_ID   App Store Connect API issuer UUID.
#   IOS_APP_PROFILE_SPECIFIER     App Store provisioning profile name for the app.
#   IOS_SHARE_PROFILE_SPECIFIER   App Store provisioning profile name for the Share extension.
#   IOS_WIDGET_PROFILE_SPECIFIER  App Store provisioning profile name for the Widget.
# Optional env (sensible defaults for this machine):
#   APP_STORE_CONNECT_KEY_ID      Default: Y6C8R5DA75
#   APP_STORE_CONNECT_KEY_PATH    Default: ~/.private_keys/AuthKey_<KEY_ID>.p8
#   APPLE_TEAM_ID                 Default: 8X4ZN58TYH
#   VERSION                       Default: contents of ./VERSION
#   BUILD_NUMBER                  Default: unix timestamp
  # SENTRY_DSN                    Optional; enables Sentry in release builds when set.
  # SENTRY_ENVIRONMENT            Optional; defaults to production in CI.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR="$ROOT_DIR/clients/apps"

APP_STORE_CONNECT_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-Y6C8R5DA75}"
APP_STORE_CONNECT_KEY_PATH="${APP_STORE_CONNECT_KEY_PATH:-$HOME/.private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-8X4ZN58TYH}"
VERSION="${VERSION:-$(cat "$ROOT_DIR/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%s)}"
# Baked into Info.plist via the $(CAPTURE_API_SECRET) build setting so the app can
# authenticate to the gated backend. Empty in local dev builds (talks to a local backend).
CAPTURE_API_SECRET="${CAPTURE_API_SECRET:-}"
CAPTURE_BACKEND_HOST="${CAPTURE_BACKEND_HOST:-}"
CAPTURE_POWERSYNC_HOST="${CAPTURE_POWERSYNC_HOST:-}"
SENTRY_DSN="${SENTRY_DSN:-}"
SENTRY_ENVIRONMENT="${SENTRY_ENVIRONMENT:-production}"

: "${APP_STORE_CONNECT_ISSUER_ID:?Set APP_STORE_CONNECT_ISSUER_ID (App Store Connect API issuer UUID)}"
: "${IOS_APP_PROFILE_SPECIFIER:?Set IOS_APP_PROFILE_SPECIFIER (installed App Store profile name)}"
: "${IOS_SHARE_PROFILE_SPECIFIER:?Set IOS_SHARE_PROFILE_SPECIFIER (installed App Store profile name)}"
: "${IOS_WIDGET_PROFILE_SPECIFIER:?Set IOS_WIDGET_PROFILE_SPECIFIER (installed App Store profile name)}"
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
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  IOS_APP_PROFILE_SPECIFIER="$IOS_APP_PROFILE_SPECIFIER" \
  IOS_SHARE_PROFILE_SPECIFIER="$IOS_SHARE_PROFILE_SPECIFIER" \
  IOS_WIDGET_PROFILE_SPECIFIER="$IOS_WIDGET_PROFILE_SPECIFIER" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  SENTRY_DSN="$SENTRY_DSN" \
  SENTRY_ENVIRONMENT="$SENTRY_ENVIRONMENT" \
  CAPTURE_BACKEND_HOST="$CAPTURE_BACKEND_HOST" \
  CAPTURE_POWERSYNC_HOST="$CAPTURE_POWERSYNC_HOST" \
  CAPTURE_API_SECRET="$CAPTURE_API_SECRET"

EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>dev.crmitchelmore.capture.ios</key><string>${IOS_APP_PROFILE_SPECIFIER}</string>
    <key>dev.crmitchelmore.capture.ios.share</key><string>${IOS_SHARE_PROFILE_SPECIFIER}</string>
    <key>dev.crmitchelmore.capture.ios.widget</key><string>${IOS_WIDGET_PROFILE_SPECIFIER}</string>
  </dict>
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
  -authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"

echo "✅ Uploaded. Build will appear in TestFlight after Apple processing (5-30 min)."
