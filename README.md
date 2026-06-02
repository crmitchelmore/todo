# Capture — fast-capture, AI-organised, agent-backed todo system

A speed-of-capture todo system for **iOS + macOS + web** that auto-suggests a due date and
category on entry, enriches items from your **personal data sources** (Obsidian vault, Gmail,
Apple Calendar, web, location), and uses an **autonomous agent running on your OpenClaw Mac Mini**
to research and optionally *do* tasks — with a **mandatory, quick human confirmation** of every
item's structure before anything is saved.

> Status: design + planning. Work is tracked in [beads](#issue-tracking-beads) (`bd`).

## Why build instead of buy

Deep research (June 2026) into commercial tools (Saner.AI, Lindy, Motion, Reclaim, Akiflow,
Todoist AI, Things 3, Sunsama, Notion AI, ClickUp Brain, Taskade, Shortwave …) and open-source
projects confirmed the gap is **real and structural**. No single product combines:

- **Obsidian live vault integration** — zero native support anywhere
- **Self-hosted agent on your own hardware** (the Mac Mini) — no commercial support
- The **Gmail-to-completion autonomous loop with personal confirm-before-save**

See [`docs/research-prior-art.md`](docs/research-prior-art.md) for the full landscape and the
open-source patterns we will copy rather than reinvent.

## Architecture (summary)

Four planes, bridged across **two Apple accounts** (iPhone/laptop = account A; Mac Mini = account B).
A **self-hosted Postgres + PowerSync** core makes sync **account-agnostic**, so the Mini agent
shares the same database instead of trying to join iCloud.

1. **Capture & sync** — SwiftUI (iOS+macOS) + React web, one shared data model via PowerSync.
   Native fast-capture: Share Sheet, Siri/Shortcuts, widgets, mac global hotkey.
2. **Brain** — OpenClaw agent on the Mac Mini: enrichment, research, optional execution.
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
- **M2** OpenClaw agent backend + richer enrichment + HITL
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
