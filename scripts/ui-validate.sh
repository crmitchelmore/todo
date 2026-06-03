#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_ROOT="${UI_ARTIFACT_DIR:-"$ROOT/.ui-artifacts/$(date -u +%Y%m%dT%H%M%SZ)"}"
IOS_DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
IOS_BUNDLE_ID="dev.crmitchelmore.capture.ios"
MAC_BUNDLE_ID="dev.crmitchelmore.capture.mac"

usage() {
  cat <<'USAGE'
Usage: scripts/ui-validate.sh [web|ios|mac|all ...]

Runs the AI-facing UI validation loop and writes screenshots/logs under .ui-artifacts/.

Environment:
  E2E_BASE_URL       Use an already-running web app instead of local Vite preview.
  UI_ARTIFACT_DIR   Output directory for screenshots and logs.
  IOS_DESTINATION   xcodebuild simulator destination (default: iPhone 15 Pro, iOS 26.5).
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

surfaces=("$@")
if [[ ${#surfaces[@]} -eq 0 ]]; then
  surfaces=(web ios mac)
fi
if [[ " ${surfaces[*]} " == *" all "* ]]; then
  surfaces=(web ios mac)
fi

mkdir -p "$ARTIFACT_ROOT"
echo "UI artefacts: $ARTIFACT_ROOT"

run_web() {
  echo "== web =="
  mkdir -p "$ARTIFACT_ROOT/web"
  (
    cd "$ROOT/web"
    UI_ARTIFACT_DIR="$ARTIFACT_ROOT/web" npm run validate:ui
  )
}

booted_simulator() {
  xcrun simctl list devices booted | awk -F '[()]' '/Booted/ { print $2; exit }'
}

run_ios() {
  echo "== iOS simulator =="
  mkdir -p "$ARTIFACT_ROOT/ios"
  (
    cd "$ROOT/clients/apps"
    xcodegen generate >/dev/null
    xcodebuild -project Capture.xcodeproj \
      -scheme CaptureiOS \
      -destination "$IOS_DESTINATION" \
      -derivedDataPath DerivedData/UIValidation \
      build CODE_SIGNING_ALLOWED=NO > "$ARTIFACT_ROOT/ios/xcodebuild.log"
  )

  local device
  device="$(booted_simulator)"
  if [[ -z "$device" ]]; then
    local name
    name="$(sed -E 's/.*name=([^,]+).*/\1/' <<<"$IOS_DESTINATION")"
    xcrun simctl boot "$name" >/dev/null || true
    device="$(booted_simulator)"
  fi
  [[ -n "$device" ]] || { echo "No booted iOS simulator found"; exit 1; }
  xcrun simctl bootstatus "$device" -b >/dev/null

  local app_path
  app_path="$(find "$ROOT/clients/apps/DerivedData/UIValidation/Build/Products" -name 'CaptureiOS.app' -type d | head -1)"
  [[ -n "$app_path" ]] || { echo "CaptureiOS.app not found"; exit 1; }
  xcrun simctl install "$device" "$app_path"
  xcrun simctl launch --terminate-running-process "$device" "$IOS_BUNDLE_ID" > "$ARTIFACT_ROOT/ios/launch.log"
  sleep 3
  xcrun simctl io "$device" screenshot "$ARTIFACT_ROOT/ios/capture-ios.png"
  xcrun simctl spawn "$device" log show --last 2m --style compact \
    --predicate 'process == "CaptureiOS" AND (eventMessage CONTAINS[c] "fatal" OR eventMessage CONTAINS[c] "uncaught" OR eventMessage CONTAINS[c] "exception")' \
    > "$ARTIFACT_ROOT/ios/error-log.txt" 2>/dev/null || true
  if grep -Eiq 'fatal|uncaught|exception' "$ARTIFACT_ROOT/ios/error-log.txt"; then
    echo "iOS runtime errors found in $ARTIFACT_ROOT/ios/error-log.txt"
    exit 1
  fi
}

run_mac() {
  echo "== macOS app =="
  mkdir -p "$ARTIFACT_ROOT/mac"
  (
    cd "$ROOT/clients/apps"
    xcodegen generate >/dev/null
    xcodebuild -project Capture.xcodeproj \
      -scheme CaptureMac \
      -destination 'platform=macOS' \
      -derivedDataPath DerivedData/UIValidation \
      build CODE_SIGNING_ALLOWED=NO > "$ARTIFACT_ROOT/mac/xcodebuild.log"
  )

  local app_path
  app_path="$(find "$ROOT/clients/apps/DerivedData/UIValidation/Build/Products" -name 'CaptureMac.app' -type d | head -1)"
  [[ -n "$app_path" ]] || { echo "CaptureMac.app not found"; exit 1; }
  open -n "$app_path"
  sleep 4
  screencapture -x "$ARTIFACT_ROOT/mac/capture-mac.png" || {
    echo "macOS screenshot failed; grant Screen Recording to the terminal/agent app and rerun." >&2
    exit 1
  }
  osascript -e "tell application id \"$MAC_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
}

for surface in "${surfaces[@]}"; do
  case "$surface" in
    web) run_web ;;
    ios) run_ios ;;
    mac) run_mac ;;
    *) usage; echo "Unknown surface: $surface"; exit 1 ;;
  esac
done

echo "UI validation complete: $ARTIFACT_ROOT"
