# Capture — fast-capture, AI-organised, agent-backed todo system

A speed-of-capture todo system for **iOS + macOS + web** that auto-suggests a due date and
category on entry, enriches items from your **personal data sources** (Obsidian vault, Gmail,
Apple Calendar, web, location), and uses an **autonomous agent running through a local harness
on your selected backend computer** to research and optionally *do* tasks — with a **mandatory,
quick human confirmation** of every item's structure before anything is saved.

> Status: **M1 (capture→suggest→confirm→sync) and M2 foundation (background enrichment worker)
> are built and verified** on a PowerSync stack (deployed to Railway), with native UIKit/AppKit clients and a
> React web client. See [Build & run](#build--run) and [Review steps](#review-steps). Remaining
> milestones (Mini agent, Obsidian, Gmail, EventKit) are tracked in [beads](#issue-tracking-beads).

## Why build instead of buy

Deep research (June 2026) into commercial tools (Saner.AI, Lindy, Motion, Reclaim, Akiflow,
Todoist AI, Things 3, Sunsama, Notion AI, ClickUp Brain, Taskade, Shortwave …) and open-source
projects confirmed the gap is **real and structural**. No single product combines:

- **Obsidian live vault integration** — zero native support anywhere
- **Self-hosted agent on your own hardware** (a selected local backend computer) — no commercial support
- The **Gmail-to-completion autonomous loop with personal confirm-before-save**

See [`docs/research-prior-art.md`](docs/research-prior-art.md) for the full landscape and the
open-source patterns we will copy rather than reinvent.

## Architecture (summary)

Four planes, bridged across **multiple Apple devices/accounts** (iPhone/laptop plus whichever Mac is
selected as the local backend computer). A **hosted Postgres + PowerSync** core (deployed to Railway)
makes sync **account-agnostic**, so the local agent shares the same database instead of trying to join iCloud.

1. **Capture & sync** — native UIKit (iOS) + AppKit (macOS), no JS-wrapped frameworks, plus a React web app; one shared data model via PowerSync (native Swift SDK on Apple platforms).
   Native fast-capture: Share Sheet, Siri/Shortcuts, widgets, mac global hotkey.
2. **Brain** — local harness on the selected backend computer: enrichment, research, optional execution.
3. **Enrichment** — on-device instant date/category suggestion; richer LLM enrichment on the Mini.
4. **Confirm UX** — every proposal surfaces as a fast confirm card; nothing saves without it.

Items flow through a lifecycle: **proposed → confirmed → active → done**. Only *confirmed* items
become real todos.

Full detail: [`docs/architecture.md`](docs/architecture.md).

## Tech choices (from research)

| Concern | Choice |
|---|---|
| Cross-platform sync | PowerSync (SQLite↔Postgres; native Swift + web SDKs; self-hostable) |
| Task schema reference | vikunja `pkg/models/tasks.go`; Obsidian Dataview frontmatter for interop |
| NL date parsing | chrono-node (client) + Recognizers-Text / Duckling (server, recurrence) |
| AI enrichment | structured LLM output (Instructor + schema) with confidence + provenance |
| Obsidian access | Local REST API plugin + embedding search |
| Email | Gmail API: rule pre-filter → LLM extraction with `source_quote` provenance |
| Agent HITL | LangGraph `interrupt_before` + durable checkpointer |
| Calendar | Apple EventKit |

## Roadmap (thin, shippable slices)

- **M1** Capture → on-device suggest → confirm → save + sync (no Mini yet)
- **M2** local harness backend + richer enrichment + HITL
- **M3** Obsidian context + write-back
- **M4** Gmail extraction + completion detection
- **M5** Apple Calendar feasibility
- **M6** Autonomous discovery + low-risk execution (location + web)

## Issue tracking (beads)

This repo uses **[beads](https://github.com/steveyegge/beads)** (`bd`) for dependency-aware issues.

```bash
bd ready            # work with no active blockers
bd show <id>        # issue detail
bd dep tree <id>    # dependency tree
bd update <id> --claim   # claim work
bd close <id>       # complete
```

Prefix is `cap-`. The full plan is seeded as 11 epics + decisions + tasks with dependencies.

## Build & run

Prerequisites: Docker/Podman (`docker compose`), Node 20+, Xcode 26 (for native apps).

```bash
# 1. Bring up the sync stack locally (Postgres source + Postgres bucket storage + PowerSync + backend + enrichment worker)
cp .env.example .env            # dev defaults; put real secrets in ignored .env.local/keychain
docker compose up -d --build
curl -s localhost:8080/probes/liveness   # PowerSync healthy

# 2. Web client (fastest dev loop)
cd web && npm install && npm run dev      # http://localhost:5173

# 3. macOS app (AppKit)
cd clients/apps && GIT_CONFIG_COUNT=0 xcodegen generate
GIT_CONFIG_COUNT=0 xcodebuild -project Capture.xcodeproj -scheme CaptureMac \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

# 4. Shared Swift core: unit tests + end-to-end data-path probe
cd clients/CaptureCore && GIT_CONFIG_COUNT=0 swift test        # 7/7
GIT_CONFIG_COUNT=0 swift run CaptureProbe                      # captures+confirms a row via the Swift SDK
```

> `GIT_CONFIG_COUNT=0` is required so SwiftPM can fetch tagged deps in this environment.
> The generated `Capture.xcodeproj` is git-ignored — regenerate it with `xcodegen generate`.
> The iOS UIKit target builds from the same `CaptureCore`; full compile needs an installed iOS
> simulator platform.

### What runs in the background (M2 enrichment)

Capture is a single instant local write (`status=proposed`) with a cheap on-device suggestion.
The `worker/` service then polls Postgres, computes a **richer** suggestion (more categories,
urgency, better date parsing — LLM-upgradable via `OPENAI_API_KEY`) and patches the
`suggested_*` fields. It **never** changes status: the human still confirms structure before save.
The patch syncs straight back to every client.

Secrets for local agents, Railway deploys, Obsidian, Gmail, and LLM enrichment should be loaded via
`scripts/with-secrets.sh <command>` from ignored `.env.local` files or macOS Keychain service
`capture`. Do not add real credentials to tracked `.env.example` files.

## Review steps

A reviewer can verify the system end-to-end:

1. **Stack health** — `docker compose ps` (pg-db, powersync, backend, worker up);
   `curl -s localhost:8080/probes/liveness`.
2. **Web capture→confirm→sync** — open the web app, type
   `email Kate the report tomorrow 2pm`, see an instant proposed row with a suggested
   `Tomorrow 14:00` / `work`; confirm; then
   `docker compose exec -T pg-db psql -U postgres -d postgres -c "select title,status,due_at,category from tasks order by created_at desc limit 3;"`
   shows it `active` in Postgres.
3. **Background enrichment** — capture something with no obvious category client-side (e.g.
   `dentist appointment next tuesday`); within a couple of seconds the proposed row's
   `suggestion_source` flips to `server` with an improved category/date (worker logs:
   `docker compose logs worker`).
4. **Native data path** — `cd clients/CaptureCore && GIT_CONFIG_COUNT=0 swift run CaptureProbe`
   prints a `PROBE_ID`; confirm that row landed:
   `docker compose exec -T pg-db psql -U postgres -d postgres -c "select id,status,category from tasks where id='<PROBE_ID>';"`.
5. **macOS app** — build (command above), launch, capture with the in-window field or ⌥Space
   global hotkey; verify the proposed row appears and confirm moves it to the active list.
6. **Unit tests** — `cd clients/CaptureCore && GIT_CONFIG_COUNT=0 swift test` (suggester) and
   `cd web && npm run build` (web typechecks/builds).
7. **Code review focus** — write-path allowlist `backend/src/index.ts` (`ALLOWED_COLUMNS`);
   capture-first instant write `clients/CaptureCore/Sources/CaptureCore/TaskStore.swift` and
   `web/src/lib/tasks.ts`; enrichment never mutates status `worker/src/index.ts`.

### Needs your credentials / hardware (not runnable here)

These milestones are scaffolded in beads and the architecture but require your accounts/local backend Mac:
local harness runner on the selected backend computer, Obsidian Local REST API (`cap-ue0`),
Gmail OAuth2 extraction (`cap-nes`, `cap-cmc`), Apple Calendar EventKit (`cap-l20`). The
enrichment worker is the local stand-in for server-side enrichment — point it at the
same Postgres to run it on the selected backend computer.

## Deploy

The backend, PowerSync, Postgres (source + bucket storage) and enrichment worker are deployed to
**[Railway](https://railway.app)** (project `capture`, four services on one private network).
Clients reach two public domains — `backend-production-de2f.up.railway.app` and
`powersync-production-e560.up.railway.app`. Native apps default to these via
`CaptureConfig.production`; the web client reads `VITE_BACKEND_URL` / `VITE_POWERSYNC_URL`.

See [`docs/deployment.md`](docs/deployment.md) for the full runbook, env-var table, `railway up`
commands, verification curls, and the Railway gotchas (private-domain suffix, PowerSync `sslmode`,
first-init Postgres password).
