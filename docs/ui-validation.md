# AI UI validation loop

Capture uses a fast “build → screenshot/inspect → fix → rerun” loop so agents can catch broken UI without waiting for manual testing.

## One-command checks

```bash
scripts/ui-validate.sh web      # Playwright smoke + screenshot
scripts/ui-validate.sh ios      # build, install, launch simulator, screenshot
scripts/ui-validate.sh mac      # build, launch macOS app, screenshot
scripts/ui-validate.sh all
```

Artefacts are written to `.ui-artifacts/<timestamp>/`. Set `UI_ARTIFACT_DIR` to control the output path. For web against production, set `E2E_BASE_URL=https://web-production-9267a.up.railway.app`.

The web smoke test specifically checks the auth gate that previously broke: email/password fields must be visible, editable, non-collapsed, and console-clean across desktop and mobile Chrome.

## MCP stack for agents

Use these MCP servers when an agent needs interactive inspection instead of just screenshots:

| Surface | Tool | Why |
| --- | --- | --- |
| Web | `microsoft/playwright-mcp` via `npx @playwright/mcp@latest` | Accessibility-tree browser control, console inspection, screenshots. |
| iOS | `getsentry/XcodeBuildMCP` plus `joshuayoes/ios-simulator-mcp` | Build/install/launch through Xcode, then inspect/tap/type/screenshot the simulator. |
| macOS | `getsentry/XcodeBuildMCP` plus `desktop-pilot-mcp` | Build the app, then inspect native AppKit accessibility trees and capture screenshots. |

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
    "desktop-pilot": {
      "command": "npx",
      "args": ["-y", "desktop-pilot-mcp"]
    }
  }
}
```

Prerequisites:

1. `xcodebuildmcp`: Node 18+ and Xcode 16+; optional global install with `brew tap getsentry/xcodebuildmcp && brew install xcodebuildmcp`.
2. `ios-simulator-mcp`: Node, Xcode simulators, and IDB (`brew tap facebook/fb && brew install idb-companion` plus the Python `idb` client if needed).
3. `desktop-pilot-mcp`: grant Accessibility permission to the terminal/agent app. Grant Screen Recording only when screenshots are required.

## Agent workflow

1. Run `scripts/ui-validate.sh web ios mac` after UI changes.
2. Inspect `.ui-artifacts/` screenshots/logs. If using MCP, prefer semantic snapshots (`playwright` accessibility tree, `ios-simulator` `ui_describe_all`, `desktop-pilot` `pilot_snapshot`) before pixel screenshots.
3. Fix the smallest UI issue found.
4. Rerun only the affected surface, then rerun `all` before shipping.

Keep validation focused on speed and productivity: login/capture/detail surfaces should render without console/runtime errors, primary inputs must be editable, and no critical controls should collapse or disappear at common mobile/desktop widths.
