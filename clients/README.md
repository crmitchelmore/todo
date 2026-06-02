# Capture — native clients (iOS UIKit + macOS AppKit)

Native Swift clients sharing a single core. **No SwiftUI, no JS-wrapped frameworks** — UIKit on
iOS, AppKit on macOS, for maximum capture performance.

## Layout

```
clients/
  CaptureCore/                 Swift package — the shared heart (builds + 7 tests pass)
    Sources/CaptureCore/
      Models.swift             TaskItem, TaskStatus, categories
      Schema.swift             PowerSync AppSchema (mirrors Postgres public.tasks)
      Suggester.swift          on-device instant date (NSDataDetector) + category guess
      Connector.swift          auth + write path to the backend /api/data contract
      TaskStore.swift          capture-first: instant local write, background enrich, watch streams
      DueFormatter.swift       relative due-date strings
    Sources/CaptureProbe/      headless end-to-end verification of the native data path
    Tests/CaptureCoreTests/
  apps/
    project.yml                XcodeGen spec (CaptureiOS + CaptureMac targets)
    CaptureiOS/Sources/        UIKit app (capture field + proposed/active lists + confirm screen)
    CaptureMac/Sources/        AppKit app (NSTextField capture, ⌥Space global hotkey, table views)
```

## Capture-first contract

`TaskStore.capture()` does a **single instant local SQLite insert** (`status=proposed`) with a
cheap on-device suggestion and returns immediately — zero `await` on network or LLM. Enrichment and
sync happen in the background and patch the row. Nothing becomes a real todo until the human
confirms via the confirm card. This mirrors `web/src/lib/tasks.ts`.

## Build / test / run

```bash
# Unit tests (suggester)
cd CaptureCore && GIT_CONFIG_COUNT=0 swift test

# End-to-end probe against a running stack (see repo root README → Build & run)
GIT_CONFIG_COUNT=0 swift run CaptureProbe

# Generate the Xcode project (it is git-ignored — regenerate after editing project.yml/sources)
cd ../apps && GIT_CONFIG_COUNT=0 xcodegen generate

# macOS app
GIT_CONFIG_COUNT=0 xcodebuild -project Capture.xcodeproj -scheme CaptureMac \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

> `GIT_CONFIG_COUNT=0` is required so SwiftPM can fetch the tagged PowerSync Swift SDK in this
> environment. The iOS target builds from the same `CaptureCore`; a full iOS compile needs an
> installed iOS simulator platform.
