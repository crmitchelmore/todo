# Architecture

## Constraints

- **Two Apple accounts.** iPhone + main laptop are on personal iCloud account **A**; the OpenClaw
  Mac Mini runs a **separate Apple account B**. The Mini cannot join account A's private iCloud
  sync. → sync must be **account-agnostic**.
- **Web client required**, alongside iOS + macOS → the data model and sync must be
  **client-agnostic** (not Apple-only).
- **Mandatory human confirmation** of item structure before save; confirmation must be effortless.
- **LLM/privacy:** cloud LLMs acceptable.
- **Autonomy:** auto-execute low-risk/reversible actions; approval for consequential ones.

## Key decision: self-hosted sync core (not CloudKit)

Because of the web client and the two-account split, the todo data lives in a **self-hosted
Postgres + PowerSync** backend rather than iCloud/CloudKit. This:

- Gives **native Swift + web SDKs** over one shared SQL data model (offline-first).
- Is **account-agnostic** — removes the cross-Apple-account bridge entirely.
- Lets the **Mac Mini agent share the same database**, so "the bridge" collapses into the sync layer.

Alternative considered: Automerge (CRDT, native Swift). Choose it only if concurrent multi-device
edits of the *same* task are common; otherwise PowerSync's per-row last-write-wins is simpler.
Tracked as decision `D-sync`.

## Planes

```
            ┌──────────────────────── Account A (personal) ────────────────────────┐
            │  iOS app        macOS app                         Web app             │
 Capture &  │  (UIKit)        (AppKit)                          (React)             │
   sync     │     │  Share Sheet / Siri / Shortcuts / widget / hotkey               │
            │     └──────────────┬───────────────┬──────────────┘                  │
            └────────────────────┼───────────────┼─────────────────────────────────┘
                                 │  PowerSync (offline-first SQLite)
                          ┌──────▼───────────────▼──────┐
            Sync core     │  Postgres + PowerSync service │  (self-hosted: Mac Mini behind Tailscale)
                          └──────▲───────────────▲──────┘
            ┌────────────────────┼───────────────┼──────────── Account B (Mac Mini) ┐
   Brain    │  OpenClaw agent  ──┘   shares DB    │                                  │
            │   • enrichment (LLM, structured output, recurrence)                    │
            │   • Obsidian (Local REST API + embeddings)                             │
            │   • Gmail (extract + completion signals)                               │
            │   • web + location                                                     │
            │   • HITL via LangGraph interrupt_before                                │
            └────────────────────────────────────────────────────────────────────-─┘
```

## Item lifecycle

```
capture ──> proposed ──(human confirm)──> confirmed ──> active ──> done
                │                                          │
        agent/email/enrichment                         (agent may
         attach suggestions                         auto-complete w/ confirm)
```

Only **confirmed** items are real, visible todos. Proposals from any source (capture suggestion,
Gmail extraction, agent result, completion detection) land as `proposed` and must pass the
confirm card.

## Confirm-before-save

Every proposal renders as a **confirm card** on all clients with one-keystroke / one-swipe
accept, quick inline edit, and reject. Agent proposals carry **confidence + provenance**
(e.g. the `source_quote` from an email) so confirmation is fast and trustworthy.

## Enrichment pipeline

1. **On-device, instant** (offline, no Mini): date via chrono-node (web) / NSDataDetector (Swift);
   lightweight category guess. Gives immediate feedback on capture.
2. **Server-side, richer** (Mac Mini): structured LLM output (schema with project, priority, tags,
   due, recurrence, confidence, provenance); recurrence via Recognizers-Text / Duckling sidecar.

## Agent & HITL

OpenClaw agent on the Mini runs LangGraph flows with `interrupt_before` on risky nodes and a
durable checkpointer. Flow: agent proposes → state serialised → pushed to a confirm card / approval
queue → resume or abort on the human decision. An **autonomy policy engine** classifies actions by
risk/reversibility: low-risk auto-executes; consequential actions require explicit approval. Item
**structure is always confirmed** regardless of autonomy level.

## Integrations

- **Obsidian:** Local REST API plugin (read/search/PATCH) + embedding search for note context;
  write tasks back to daily notes in the obsidian-tasks emoji format.
- **Gmail:** OAuth2; rule-based pre-filter then LLM extraction with `source_quote` provenance;
  completion detection from replies / label changes (suggested, never auto-applied without confirm).
- **Apple Calendar:** EventKit (from the Apple-native client) for free/busy → feasibility scoring.

See `research-prior-art.md` for the specific open-source repos and patterns adopted for each.
