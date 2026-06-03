# Capture — Product Objectives & Values

A fast-capture, AI-organised, agent-backed todo system for **iOS + macOS + web**.

## Mission

Make capturing a todo effortless and instant, then let software do the organising —
suggesting a due date and category, enriching from your personal data, and (where safe)
researching or even *doing* the task — while **you** stay in control of what gets saved.

## Objectives

1. **Frictionless capture.** From any surface (global hotkey, Share Sheet, Siri/Shortcuts,
   widgets, web, paste-a-markdown-list) an item is captured in a single instant local write.
2. **Auto-organisation.** Every item gets a suggested due date and category on entry —
   on-device for instant offline guesses, upgraded by a background worker (and, later, the
   Mac Mini agent) for richer enrichment.
3. **Personal-context awareness.** Enrich items from the user's own data: Obsidian vault,
   Gmail, Apple Calendar, the web, and current location.
4. **Agentic discovery & execution.** An always-on agent on the user's OpenClaw Mac Mini
   researches items and, for low-risk reversible work, can act — surfacing results as proposals.
5. **Email-driven completion suggestions.** Detect likely-done work from incoming mail and
   propose marking items complete.
6. **Sync everywhere, own your data.** One account, one set of todos, synced across all
   surfaces on a self-hosted Postgres + PowerSync core.

## Values (non-negotiable principles)

- **Speed is the priority.** Capture is a single instant local write (`status=proposed`) with
  **zero** await on network or LLM. Suggestions and enrichment run in the background and patch
  the row. Nothing about capture blocks on a round-trip.
- **Human confirms before save.** Every proposal surfaces as a fast confirm card — a keystroke
  or swipe to accept, edit, or reject. **Nothing is saved without explicit confirmation.**
- **Bounded autonomy.** Auto-execute only low-risk, reversible work; anything consequential
  waits for approval. The agent proposes; the human disposes.
- **Native and performant.** iOS is UIKit, macOS is AppKit — no JS-wrapped frameworks for the
  native clients. Web is a separate React surface. Local-first SQLite for optimistic capture.
- **Own your data & account-agnostic sync.** A hosted Postgres + PowerSync core bridges the
  user's two Apple accounts (personal devices ↔ Mac Mini agent) without forcing one iCloud.
- **Defensive by default.** Per-user data isolation enforced at the database boundary
  (`owner_id` foreign keys + per-user sync rules), revocable opaque sessions, least-privilege
  credentials — not just application-layer checks.
- **Privacy-respecting.** Personal data (vault, mail, calendar, location) is used to help the
  user and is not exposed beyond what each integration needs.

## How it works (one line)

Capture instantly → on-device suggests date + category → background worker / Mini agent enrich →
**you confirm** → it saves and syncs to every device.

## Auth

Email + password today (per-user accounts so it's "just me, others can sign up later");
social sign-in is additive later. Credentials sit on a revocable opaque-session +
short-lived per-user sync-JWT backbone, with database-level per-user isolation.

## Status

M1 (capture → suggest → confirm → sync) and the M2 enrichment worker are built and verified on
the PowerSync stack (deployed to Railway), with native UIKit/AppKit clients and a React web
client. Remaining milestones — Mac Mini agent, Obsidian, Gmail, EventKit — are tracked in beads.
See `README.md` and `docs/architecture.md` for detail.
