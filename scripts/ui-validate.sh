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
Each run also creates design-review.md with the human-centred quality checklist agents should use
when inspecting the captured web, simulator, and macOS screenshots.

Environment:
  E2E_BASE_URL       Use an already-running web app instead of local Vite preview.
  UI_ARTIFACT_DIR   Output directory for screenshots and logs.
  IOS_DESTINATION   xcodebuild simulator destination (default: iPhone 17, iOS 26.5).
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

cat > "$ARTIFACT_ROOT/design-review.md" <<'REVIEW'
# Capture UI design review

Use this checklist after `scripts/ui-validate.sh web ios mac` creates screenshots and logs.

## Product grammar
- [ ] The surface still reads as Capture: command deck, triage queue, active outline, inspector-card stack.
- [ ] Amber is used for human decisions, iris/purple for AI evidence, mint for completion/sync.
- [ ] The UI supports capture-first flow: the primary input is obvious, fast, and not visually crowded.

## Cross-platform parity
- [ ] Web, Mac, and iOS expose the same core capabilities for capture, confirmation, active work, rejected items, taxonomy, AI handoff, and rules.
- [ ] Differences are platform-native rather than capability gaps.
- [ ] Keyboard/simulator/mobile layouts do not hide primary auth or capture controls.

## Usability and stability
- [ ] Primary controls are visible, reachable, and have enough hit area at desktop and mobile sizes.
- [ ] Inspector/detail panes use available space without collapsing or looking sparse.
- [ ] No console/runtime/fatal errors appear in the captured logs.
- [ ] Empty states explain what to do next without sounding generic.

## Evidence to cite before shipping
- Web: `web/` Playwright screenshot and console-clean run.
- iOS: `ios/capture-ios.png`, `ios/xcodebuild.log`, `ios/error-log.txt`.
- Mac: `mac/capture-mac.png`, `mac/xcodebuild.log`.
REVIEW

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
    GIT_CONFIG_COUNT=0 xcodegen generate >/dev/null
    GIT_CONFIG_COUNT=0 xcodebuild -project Capture.xcodeproj \
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
  # Simulator can show system banners (for example Apple Intelligence prompts) over the app after
  # boot. Dismiss transient overlays so the screenshot proves Capture UI quality, not SpringBoard.
  if pgrep -x "Simulator" >/dev/null; then
    osascript -e 'tell application "Simulator" to activate' \
              -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
  fi
  sleep 2
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
    GIT_CONFIG_COUNT=0 xcodegen generate >/dev/null
    GIT_CONFIG_COUNT=0 xcodebuild -project Capture.xcodeproj \
      -scheme CaptureMac \
      -destination 'platform=macOS' \
      -derivedDataPath DerivedData/UIValidation \
      build CODE_SIGNING_ALLOWED=NO > "$ARTIFACT_ROOT/mac/xcodebuild.log"
  )

  local app_path
  app_path="$(find "$ROOT/clients/apps/DerivedData/UIValidation/Build/Products" -name 'CaptureMac.app' -type d | head -1)"
  [[ -n "$app_path" ]] || { echo "CaptureMac.app not found"; exit 1; }
  open -n "$app_path"
  local frontmost="" window_count=0
  for _ in {1..10}; do
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose bundle identifier is \"$MAC_BUNDLE_ID\") to true" >/dev/null 2>&1 || true
    sleep 1
    frontmost="$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null || true)"
    window_count="$(osascript -e "tell application \"System Events\" to count windows of (first process whose bundle identifier is \"$MAC_BUNDLE_ID\")" 2>/dev/null || echo 0)"
    if [[ ( "$frontmost" == "CaptureMac" || "$frontmost" == "Capture" ) && "${window_count:-0}" -ge 1 ]]; then
      break
    fi
  done
  if [[ "$frontmost" != "CaptureMac" && "$frontmost" != "Capture" ]]; then
    echo "CaptureMac is not frontmost after launch (frontmost=$frontmost)." > "$ARTIFACT_ROOT/mac/frontmost.txt"
    echo "The app may be blocked by a keychain/system prompt; screenshot would not prove Capture UI quality." >&2
    exit 1
  fi
  if [[ "${window_count:-0}" -lt 1 ]]; then
    echo "CaptureMac launched but no app window was visible." > "$ARTIFACT_ROOT/mac/frontmost.txt"
    exit 1
  fi
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
