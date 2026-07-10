# ADR 0001: Capture architecture planes and account bridge

## Status

Accepted.

## Context

Capture must be instant on iOS, macOS, and web while still supporting slower AI enrichment, personal-context lookup, and future agent execution. The user’s main devices may share one Apple account, while the selected local backend Mac may use another account, so private iCloud/CloudKit alone cannot be the shared backend.

## Decision

Use four planes:

1. **Capture plane** — native iOS/UIKit, macOS/AppKit, and web clients write a local-first PowerSync task row immediately. Capture never waits for network or LLM work.
2. **Sync plane** — Postgres + PowerSync on the Mac mini is the account-agnostic source of truth. Every row is owner-scoped by backend auth and sync rules, so other devices can participate without joining the Mac’s iCloud account.
3. **Enrichment/agent plane** — background workers and local harness agents read proposed work, add suggestions/events, and request approval for consequential actions.
4. **Confirmation plane** — users confirm or edit task structure before a proposed item becomes active. AI/agent output lands as proposals or task history, not silent irreversible changes.

## Consequences

- Fast capture stays a single local write; background enrichment patches suggestions and appends history.
- The database is the trust boundary: ownership, allowed upload tables, and append-only `task_events` prevent clients or agents from forging history or crossing users.
- Projects use recursive `tasks.parent_task_id` links rather than a separate project table. The
  database enforces same-owner parent/child relationships and rejects cycles; child task history
  can be rolled up for parent/project presentation without duplicating events.
- iCloud is not a dependency for cross-device sync or the Mac Mini bridge.
- Personal integrations (Gmail, Obsidian, calendar, location, web) can be added behind the enrichment/agent plane without slowing capture.
- Future low-risk automation must write observable events and respect approval gates before changing consequential state.
