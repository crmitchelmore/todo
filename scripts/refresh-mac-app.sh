#!/usr/bin/env bash
# Pull, build, install, and launch the latest local Capture Mac app.
# Existing installs are moved aside under /tmp/todo instead of being deleted.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR="$ROOT_DIR/clients/apps"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALL_APP="$INSTALL_DIR/CaptureMac.app"
BUILD_ROOT="${BUILD_ROOT:-/tmp/todo/capture-mac-build/$(date +%Y%m%d%H%M%S)}"
OLD_INSTALL_DIR="/tmp/todo/capture-mac-old-installs/$(date +%Y%m%d%H%M%S)"

cd "$ROOT_DIR"
git pull --rebase

echo "==> Generating Xcode project"
(cd "$APPS_DIR" && GIT_CONFIG_COUNT=0 xcodegen generate)

echo "==> Building CaptureMac"
GIT_CONFIG_COUNT=0 xcodebuild \
  -project "$APPS_DIR/Capture.xcodeproj" \
  -scheme CaptureMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_ROOT/DerivedData" \
  build CODE_SIGNING_ALLOWED=NO

BUILT_APP="$BUILD_ROOT/DerivedData/Build/Products/Debug/CaptureMac.app"
[ -d "$BUILT_APP" ] || { echo "Built app not found: $BUILT_APP" >&2; exit 1; }

echo "==> Quitting any running Capture app"
osascript -e 'tell application id "dev.crmitchelmore.capture.mac" to quit' >/dev/null 2>&1 || true
sleep 1

mkdir -p "$OLD_INSTALL_DIR" "$INSTALL_DIR"
for app in \
  "$INSTALL_DIR/CaptureMac.app" \
  "$INSTALL_DIR/Capture.app" \
  "$HOME/Applications/CaptureMac.app" \
  "$HOME/Applications/Capture.app"
do
  if [ -e "$app" ]; then
    echo "==> Moving old install $app -> $OLD_INSTALL_DIR/"
    mv -f "$app" "$OLD_INSTALL_DIR/"
  fi
done

echo "==> Installing $INSTALL_APP"
ditto "$BUILT_APP" "$INSTALL_APP"

echo "==> Launching $INSTALL_APP"
open "$INSTALL_APP"

echo "Installed and launched CaptureMac from $(git rev-parse --short HEAD)."
echo "Old installs, if any, were moved to $OLD_INSTALL_DIR."
