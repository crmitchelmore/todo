# AI UI validation loop

Capture uses a fast “build → screenshot/inspect → fix → rerun” loop so agents can catch broken UI without waiting for manual testing.

## One-command checks

```bash
scripts/ui-validate.sh web      # Playwright smoke + screenshot
scripts/ui-validate.sh ios      # build, install, launch simulator, screenshot
scripts/ui-validate.sh mac      # build, launch macOS app, screenshot
scripts/ui-validate.sh all
```

Artefacts are written to `.ui-artifacts/<timestamp>/`. Set `UI_ARTIFACT_DIR` to control the output path. For web against production, set `E2E_BASE_URL=https://bravos-mac-mini.taile313a5.ts.net:10000`.

The web smoke test specifically checks the auth gate that previously broke: email/password fields must be visible, editable, non-collapsed, and console-clean across desktop and mobile Chrome.

## MCP stack for agents

Use these MCP servers when an agent needs interactive inspection instead of just screenshots:

| Surface | Tool | Why |
| --- | --- | --- |
| Web | `microsoft/playwright-mcp` via `npx @playwright/mcp@latest` | Accessibility-tree browser control, console inspection, screenshots. |
| iOS | `getsentry/XcodeBuildMCP` plus `joshuayoes/ios-simulator-mcp` | Build/install/launch through Xcode, then inspect/tap/type/screenshot the simulator. |
| macOS | `getsentry/XcodeBuildMCP` plus `peekaboo` | Build the app, then inspect native AppKit accessibility trees, drive permissions/UI, and capture screenshots. |
| Web portals | `webwright` skill or Playwright scripts | Repeatable code-as-action browser automation for long portal flows that are not covered by official APIs. |

Example MCP config:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest"]
    },
    "xcodebuild": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest", "mcp"]
    },
    "ios-simulator": {
      "command": "npx",
      "args": ["-y", "ios-simulator-mcp"],
      "env": {
        "IOS_SIMULATOR_MCP_DEFAULT_OUTPUT_DIR": ".ui-artifacts/ios-mcp"
      }
    },
    "peekaboo": {
      "command": "npx",
      "args": ["-y", "@steipete/peekaboo"]
    }
  }
}
```

Prerequisites:

1. `xcodebuildmcp`: Node 18+ and Xcode 16+; optional global install with `brew tap getsentry/xcodebuildmcp && brew install xcodebuildmcp`.
2. `ios-simulator-mcp`: Node, Xcode simulators, and IDB (`brew tap facebook/fb && brew install idb-companion` plus the Python `idb` client if needed).
3. `peekaboo`: install with `brew install steipete/tap/peekaboo` or run the MCP server with `npx -y @steipete/peekaboo`. Grant Screen Recording and Accessibility to the terminal/agent app; run `peekaboo permissions status` to verify. Event Synthesizing is optional for background input.
4. `webwright`: use for repeatable browser workflows such as App Store Connect / Apple Developer portal checks when an official API or CLI cannot do the job. On this machine, Apple Developer portal work can often reuse the already signed-in Safari session via AppleScript/Peekaboo; prefer that over creating a fresh browser profile that asks for Apple ID and 2FA again. Keep generated scripts and screenshots as artefacts; do not store Apple passwords or 2FA material.

## Agent workflow

1. Run `scripts/ui-validate.sh web ios mac` after UI changes.
2. Inspect `.ui-artifacts/` screenshots/logs. If using MCP, prefer semantic snapshots (`playwright` accessibility tree, `ios-simulator` `ui_describe_all`, `peekaboo see --json`) before pixel screenshots.
3. Fix the smallest UI issue found.
4. Rerun only the affected surface, then rerun `all` before shipping.

Keep validation focused on speed and productivity: login/capture/detail surfaces should render without console/runtime errors, primary inputs must be editable, and no critical controls should collapse or disappear at common mobile/desktop widths.

## Design-quality loop

Every run writes `.ui-artifacts/<timestamp>/design-review.md`. Treat it as the UI acceptance checklist:

1. Generate evidence: `scripts/ui-validate.sh web ios mac`.
2. Open the screenshots/logs and fill the checklist mentally or directly in the artefact file.
3. For web usability regressions, use Playwright/Webwright to interact with the running app rather than only reading DOM. Use system Chrome on this machine (`channel="chrome"`) because bundled Chromium can crash.
4. For iOS, build/install/launch in Simulator and inspect `ios/capture-ios.png` plus `ios/error-log.txt`.
5. For Mac, run the native app and inspect `mac/capture-mac.png`; grant Screen Recording/Accessibility if screenshots or interaction fail. If the script writes `mac/frontmost.txt`, treat that as a failed validation: a keychain/system prompt or missing app window blocked Capture, so the screenshot would not prove design quality.
6. Iterate until the surface fits `docs/capture-ux-patterns.md`: Capture should feel like a calm command cockpit, not a generic CRUD dashboard.
