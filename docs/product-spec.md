# Capture — Product Specification

> A single, technology-agnostic product specification for **Capture**: a fast-capture,
> AI-organised, agent-backed personal todo system for phone, desktop, and web.
>
> This document was produced by drafting three independent specifications (one each from
> three different AI models), cross-reviewing them for alignment with the project, and
> merging the strongest, most repo-accurate parts into one. It deliberately describes the
> product by **role and capability**, not by named technologies, so it captures what Capture
> *is* rather than what it is built with.

It has three sections, each for a different reader:

1. **Executive Summary** — the vision in a minute.
2. **Product Brief** — for product managers: the problem, the philosophy, the features and how
   they relate, the conceptual planes, and the experience principles.
3. **Engineering Detail** — the complications we resolved, the invariants that protect the
   product, and the testing posture.

---

## 1. Executive Summary

Capture exists because modern intent is scattered — across notes, email, calendar, messages,
web pages, and half-formed thoughts — while existing task tools punish that reality by forcing
you to organise everything *before* the system becomes trustworthy. Capture inverts the deal.

You record intent the instant it appears as a single, instant, **local write that never waits**
on the network, sync, or a model. Software then proposes structure and enriches the item from
your own personal context — first an instant on-device guess, then a richer background pass — and
surfaces the result as a **proposal**. Nothing becomes a real todo until you give a one-gesture
confirmation. An always-on autonomous agent running on **your own hardware** can research items
and, for low-risk reversible work, optionally act — but it always returns results as proposals
you approve. You own one set of todos, synced across every surface.

What makes Capture different is the relationship between **speed and control**: capture is
effortless, trust comes from a fast, mandatory confirmation of every item's structure, and the
agent only ever *proposes* — the human disposes. Proposals carry confidence and provenance so
confirming is quick. Projects are not a special entity or a tag — a project is simply a task with
subtasks, recursively. The result: fewer dropped commitments, less task-system maintenance, and
safe delegation of work without losing authorship.

---

## 2. Product Brief (for product managers)

### 2.1 The problem and the vision

People generate commitments faster than any tool lets them file commitments. Intent shows up
mid-conversation, mid-email, on a web page, while walking, or as a passing thought — and the cost
of "capturing it properly" (choosing a list, a due date, a project, tags) is high enough that
most intent is either lost or dumped into an unstructured pile that erodes trust. Once a task
system is no longer trusted, it is abandoned.

Capture reverses that burden by **separating the act of recording from the act of organising**.
You throw intent into the system at full speed from any surface; the system then proposes
structure, enriches from personal context, and asks for a quick confirmation before anything
becomes real work. The system gathers and suggests; the human decides.

The product shape is a **calm command cockpit**: instant capture first, a small **triage queue**
of human decisions second, an active outline of confirmed work third, and an evidence-rich
inspector for context, history, subtasks, and agent activity. Success is measured by **outcomes,
not output**: less time maintaining a task system, more trust in what is in it, and safe
automation that advances work without removing human oversight.

### 2.2 Design philosophy and non-negotiable values

Four design philosophies anchor every decision (the *why*):

- **Conceptual integrity.** One coherent model end to end — a single lifecycle, a single notion
  of "a task", a single confirmation gesture, the same grammar on every surface. Capture from a
  phone, a desktop hotkey, a pasted list, an email extraction, and an agent discovery are all
  variants of one flow, not separate products.
- **Design for production / stability.** Capture stores durable personal intent and lets
  automation touch it. Durable state must therefore be owner-scoped, constrained, auditable,
  idempotent, and safe under retries — correctness is enforced at boundaries, not assumed of
  well-behaved clients. Capture must stay instant under poor networks.
- **Outcome over output.** Suggestions, context, and agent work are valuable only when they help
  the user reach a trustworthy todo, a completed task, or a well-evidenced decision. Automation
  that produces unreviewed changes is a regression, not a feature.
- **Human-centred design.** Speed and trust are the two felt qualities. The human is always the
  author of commitments and the decision-maker for both structure and consequence.

These produce the **non-negotiable values**:

1. **Speed of capture is the priority.** Capture is one instant local write with zero await on
   network or model; the input clears immediately. Everything else happens afterwards and patches
   the item.
2. **Human confirms before save.** Every proposal — from any source — passes a fast confirm card.
   Nothing becomes a real todo without explicit confirmation.
3. **Bounded autonomy.** Only low-risk, reversible actions may auto-execute; anything
   consequential waits for explicit approval. Structure is *always* confirmed, at every autonomy
   level.
4. **Native and performant clients** on each platform, with an offline-first local store so the
   UI reflects writes immediately.
5. **Own your data and account-agnostic sync.** One owned data set, shared across separate
   authenticated identities (personal devices and the user-owned agent) through a hosted sync
   core — not any single vendor cloud.
6. **Defensive by default.** Per-user isolation enforced at the data boundary, revocable sessions,
   least-privilege credentials, bounded payloads — not just application-layer checks.
7. **Privacy-respecting use of personal data.** Personal context is used to help the user and is
   exposed no further than each integration needs.

### 2.3 The key features and how they relate

The features are not a list; they are a single flow with a few orthogonal capabilities hanging
off it.

- **Capture → suggest → enrich → confirm → sync** is the spine.
  - *Capture* is one instant local write at status `proposed`. It never waits on network, sync, a
    model, a date parser, or an agent.
  - *Suggest* is an immediate on-device guess (a due date and a category) that patches the item
    with no network round-trip, so the confirm card is useful right away — even offline.
  - *Enrich* is a richer background pass (broader categories, urgency, fuller date and recurrence
    parsing, tags, project hints, personal-context discovery, confidence, provenance) that patches
    the **same** item again.
  - *Confirm* is the mandatory human gate: a one-gesture accept / inline-edit / reject.
  - *Sync* propagates every patch and every confirmation to all surfaces.
  - The crucial relationship: **suggestion and enrichment never change an item's lifecycle status
    and never overwrite confirmed fields — only the human promotes work.** They decorate; they do
    not commit.
- **Lifecycle.** `capture → proposed → (human confirm) → confirmed → active → done`, with
  `cancelled` as the discard/reject path. Only confirmed/active items are real todos; proposed
  items are inbox decisions; done items remain queryable for history and roll-ups. Every source of
  work shares this one lifecycle.
- **Projects as recursive tasks.** A project is not a tag and not a separate entity — it is a task
  that has subtasks, and those subtasks can have their own subtasks. Every child is a normal task
  that can be captured, enriched, confirmed, completed, reopened, and audited. Parent/project views
  **roll up** child progress, recent child history, and agent activity **without mutating the
  child's own history**. Pasting a nested list preserves hierarchy: parent lines become parent
  tasks, nested lines become subtasks linked to the nearest parent, completed bullets may import as
  done. Tags remain lightweight labels, not the hierarchy model.
- **Agent, human-in-the-loop.** An always-on autonomous agent runs on the user's own hardware. It
  researches items and, for low-risk reversible work, can act — but always surfaces results as
  proposals routed through the same confirm gate. Consequential actions pause at a durable approval
  checkpoint until the human decides. **The agent proposes; the human disposes.**
- **Personal-context integrations.** A personal notes/knowledge vault, email, calendar, the web,
  and location feed proposals and enrichment. They are *categories of context*, sitting behind the
  enrichment/agent layer — never on the capture hot path — and they never silently create real
  todos or change lifecycle status.
- **Completion detection.** Personal context (for example, an email reply that reads as "done")
  can produce a *proposal* to mark an item complete — never an automatic completion. It re-enters
  the same confirm gate.

Every source of structure converges on one human gate:

```
            ┌─ on-device suggestion ─┐   ┌─ background enrichment ─┐
capture ──▶ proposed ──────────────────────────────────────────────▶ (confirm) ──▶ confirmed/active ──▶ done
              ▲           ▲                  ▲                ▲                                       │
   email / agent / completion proposals ─────┘                └── agent research / attempt results    └─ completion-detection proposal
```

Every arrow into `proposed` is a proposal that must pass the confirm gate before it changes real
work.

### 2.4 The conceptual planes (described as essence)

Capture is easiest to understand as a small number of cooperating planes, each with one
responsibility:

- **Capture & sync plane.** Native clients on each platform plus a complete browser client. Their
  job is instant local writes and reflecting synced state. Fast-capture entry points — a global
  desktop hotkey, a system share action, voice/shortcut entry, widgets, the web, and paste-a-list —
  all funnel into the same single write. Clients render optimistic state and sync in the background.
- **Hosted sync core.** An account-agnostic, owner-scoped source of truth that mirrors an
  offline-first local store on every client. It is the trust boundary: ownership, allowed write
  surfaces, and append-only history are enforced here. Because the shared core *is* the database,
  the "bridge" between separate device and agent identities collapses into the sync layer.
- **Agent / brain plane.** A self-hosted autonomous agent on user-owned hardware that performs
  research, context discovery, optional low-risk execution, and consequential-action proposals
  through durable, resumable checkpoints. It writes observable history and proposals through
  trusted paths.
- **Enrichment plane.** The two-tier model — instant on-device guess, then richer background
  enrichment. Both tiers are advisory until confirmation and only ever add suggestions and history.
- **Confirmation plane.** The triage queue is the product's trust surface. Every proposal — capture
  suggestion, email extraction, agent result, completion detection — converges into fast confirm
  cards carrying edit/accept/reject, confidence, and provenance.

### 2.5 User-experience principles

- **Command-first.** The first interactive surface is always capture; it clears instantly on
  submit and never waits on network, model, sync, or agent work. Settings, filters, and
  administration are secondary.
- **Confirm before structure.** An item may be enriched automatically, but the human confirms its
  final structure before it becomes active. Suggested fields are shown in an explicitly
  unconfirmed state and can be edited inline before accepting.
- **Approval before consequence.** Any action that mutates external state needs an approval
  checkpoint and must record completion or failure back into the item's history.
- **Local-first optimism.** The UI reflects local writes immediately and treats sync and agent work
  as evidence that lands later, asynchronously.
- **Evidence-led.** Human decisions are fast because proposals show confidence, provenance, and the
  relevant source quote — not because the user is asked to trust a black box. Human-decision
  moments, AI/agent evidence, and completion each have a distinct, consistent visual channel;
  history reads as a semantic timeline first, with raw detail behind expansion. (As a heuristic,
  low confidence can still be useful if provenance is strong, while high confidence without
  provenance should be treated carefully.)
- **Calm, dense, complete.** Proposed items are decision cards; active work is a denser outline;
  parent projects roll up child evidence; the inspector never clips horizontally. Confirm / reject
  / edit are reachable by one keystroke, click, tap, or swipe; mobile never collapses primary
  controls; the web is a complete functional surface, not an admin panel.

---

## 3. Engineering Detail

This section is framed as the **complications we resolved** — the places where the simple story
meets reality, and the deliberate choices that keep conceptual integrity intact.

A few architectural patterns recur by design and are noted where they apply: a **modular monolith**
sync core (authentication, write-path, sync rules as internal modules behind one deployable); a
**client-server** split where clients hold an optimistic local replica and the core holds the
authoritative copy; a **layered (n-tier)** arrangement (capture/UX → repository → sync → durable
store); the **repository** pattern as the single typed gateway clients use instead of touching
storage directly; **materialised / rolled-up views** for project aggregation; **idempotency** for
all automation writes; **data-transfer objects** at the sync boundary; **guard clauses / early
returns** at the API edge; and **arrange-act-assert**, behaviour-level testing.

### 3.1 The lifecycle state machine, and why enrichment cannot touch it

The canonical lifecycle:

```
capture ─▶ proposed ─(human confirm)─▶ confirmed ─▶ active ─▶ done
                                                       └─▶ cancelled (discard / reject)
```

| State | Meaning |
| --- | --- |
| `proposed` | Captured or generated; awaiting human confirmation. **Not** a real todo. |
| `confirmed` / `active` | Human-confirmed real todo; appears in the active outline. |
| `done` | Completed; retained for history and roll-ups. |
| `cancelled` | Explicitly discarded / rejected; not active work. |

The single invariant that defines the product: **only the human-confirmation path promotes
`proposed` work into active work.** Confirmation is one transactional write that stamps a durable
confirmation timestamp and moves the item into the active set. Because the gate is a durable fact
(the timestamp) rather than a transient flag, storage may legitimately collapse "confirmed" and
"active" into a single committed work state — the active outline simply reads the
confirmed-and-active rows together — without weakening the gate. Completion stamps a separate
completion timestamp; **reopening** a done task returns it to active, clears the completion
timestamp, and appends an audit event.

**Complication resolved — enrichment must write continuously without ever advancing an item.**
Enrichment and agents need to keep improving a `proposed` item (better date, category, tags,
research notes) while never promoting it. The enrichment write is therefore scoped two ways: it may
touch only suggestion fields, *and* only while the row is still `proposed`. Concretely the
background update both restricts the columns it sets and guards its filter on `status = 'proposed'`,
so a confirmation that races ahead simply causes the enrichment write to affect zero rows. Status
changes have exactly one author: the human. Transitions append **semantic events** (captured,
confirmed, updated, enriched, agent-requested, agent-completed, agent-failed, completed, reopened,
rejected, cancelled), and the history surfaces meaning first, raw detail second.

### 3.2 Capture must never block on intelligence or sync

Capture is the hot path and is designed as a local repository operation: the client generates an
identifier, stamps owner context, inserts a `proposed` row into the offline-first local store,
optionally attaches bounded previews, and returns immediately. The on-device suggestion pass runs
after (or alongside) that write and patches suggestion fields. If suggestion fails, the captured
proposal still exists; if the device is offline, the item remains durable and syncs later; if
background enrichment is delayed, the confirm card still works with the raw title and the local
guess. This is the difference between Capture and a chat-style AI tool: **the user never waits for
the system to think before their intent is safe.**

### 3.3 Data ownership, account-agnostic sync, and the concurrency choice

Every durable row that belongs to a user carries an **owner identifier**. The datastore enforces
ownership with constraints and owner-scoped indexes; sync filters rows by the authenticated owner;
and the server **forces ownership from the authenticated session** rather than trusting any
client-supplied owner. This is exactly what makes sync account-agnostic: because the shared core is
owner-scoped, a device on one identity and the agent on a *separate* identity participate in one
database purely by authenticating as the same owner. No single vendor cloud sits in the trust path,
and the user owns the data. Consistency across surfaces is **eventual and reactive** (local-first
optimistic writes, background sync), not instantaneous.

**Concurrency choice — per-row last-write-wins vs richer merge.** We adopt **per-row
last-write-wins** (most recent write to a row wins; no field-level reconciliation). The rationale
is conceptual-integrity- and stability-first: the expected workload is one identity across a few
devices plus one agent, where *concurrent edits to the same task* are rare. Last-write-wins is
dramatically simpler to reason about, test, and operate, and it keeps capture fast. We explicitly
recorded the alternative — a field-level conflict-free merge — and the trigger to adopt it: *only
if* simultaneous multi-device edits of the *same* task become common, and even then applied
selectively to the fields that need it rather than replacing the whole model. This is a reversible,
documented decision, not a permanent constraint.

**Complication resolved — account switching must not leak optimistic writes.** Local optimistic
data is cleared on a *true* account boundary (sign-out, or sign-in as a different owner). A normal
relaunch as the *same* owner keeps the local replica intact, so pending offline writes still
upload; only an actual owner change wipes local state. This prevents one account's not-yet-uploaded
writes from replaying into — or briefly displaying under — another account.

### 3.4 The recursive task model and its edge cases

A project is an ordinary task row with a self-referential parent link, producing a recursive tree.
The edge cases are resolved at the **data boundary**, not in UI code:

- **Same-owner parent/child.** A child may only reference a parent owned by the same user;
  cross-owner hierarchy is impossible. Expressed as a composite reference, e.g.
  `FOREIGN KEY (owner_id, parent_task_id) REFERENCES tasks (owner_id, id)`.
- **Reject self-parenting.** A task cannot be its own parent, e.g. `CHECK (id <> parent_task_id)`.
- **Cycle prevention.** A write-time guard walks the ancestry; if the proposed parent is already a
  descendant of the task being updated, the write is rejected — so the tree can never close into a
  ring at any depth. (Nesting is *recursive*, not literally infinite; practical depth limits may
  apply in UX.)
- **Nested-list ingestion ordering.** A pasted nested list is parsed into items that each remember
  their source position and their parent's source position. The parser recognises real list
  structure (it ignores empty bullets and does not explode ordinary prose because of a stray dash).
  Ingestion then creates **parent rows before child rows** and resolves each child's parent link
  from the source-position map, so a child is never written before the parent it must reference.
  Active items enter as `proposed`; already-completed bullets import directly as `done`. Ancestor
  titles may be retained as lightweight compatibility labels while the hierarchy remains canonical.

**Roll-ups must never mutate child history, and must not contend on writes.** Parent/project
presentation is a **materialised / rolled-up read view**: a read-path recursive aggregation walks
descendants to compute open / done / blocked / total counts and merges recent descendant history
into the parent's timeline (each descendant event shown with its child's title for context). This
is deliberately a *read-path* aggregation rather than writing summary metrics onto the parent row:
mutating the parent on every child change would cause a cascade of write locks, sync storms, and
contention. The child remains the single source of truth for its own append-only history.

### 3.5 Enrichment that never mutates status, and idempotent background processing

The enrichment pipeline is two-tier. **Tier one** is instant and on-device: a natural-language date
parse plus a lightweight category guess, written immediately after the local insert and tagged with
an on-device provenance marker, giving immediate offline feedback. **Tier two** is a background
worker that claims still-`proposed` items whose suggestion has not had a richer pass, computes a
better suggestion (broader categories, urgency, fuller date/recurrence parsing, tags, and
personal-context discovery — optionally upgraded by a structured-output language model), and patches
only the suggestion fields, upgrading the provenance marker to a server/model tier. The patch syncs
straight back to every client so the confirm card updates live. The worker is programmatically
blocked from writing core fields (title, status, the confirmed due/category): **it never changes
status and never overwrites confirmed input.**

**Idempotent, attributable, bounded background processing.** Every automation-accessible write is
safe to retry:

- **Deterministic identifiers.** Events and proposals derive their identifier deterministically from
  a **stable** content key (owner, task, type, and a fixed operation key — *not* a per-attempt
  timestamp, which would defeat deduplication). Re-running the same logical operation produces the
  same identifier, so a conflicting insert is a no-op rather than a duplicate.
- **Conflict-tolerant upserts.** History events insert with "do nothing on conflict"
  (`ON CONFLICT DO NOTHING`); proposals upsert only while still `pending`, so a human decision
  already recorded against a proposal is never silently overwritten by a later worker tick.
- **At-most-once execution via atomic claim.** An approved agent attempt is claimed by an update
  guarded on the approved state that flips the checkpoint to a resumed state and reports whether a
  row actually changed; only the tick that wins the claim executes, so overlapping ticks cannot
  double-execute.
- **Non-overlapping, bounded ticks.** The worker polls sequentially with a bounded batch size; ticks
  never overlap, and history payloads and text fields are length-bounded before they are written.
  Failed enrichment is logged and observable without corrupting task state.

### 3.6 The write-path allowlist and guard clauses at the API boundary

The sync upload boundary is deliberately small and defensive, expressed as **guard clauses / early
returns** plus a strict allowlist. The API exposes *capabilities* (register, sign in, sign out /
revoke, mint short-lived sync credentials, health/config, owner-scoped write batches, out-of-process
capture ingestion, agent handoff, proposal decisions), not raw internal power.

- **Table and column allowlist.** Only an explicit set of tables, and within each only an explicit
  set of columns, may be mutated by clients (e.g. tasks, tags, task attachments). Disallowed columns
  are **silently stripped** by a sanitiser; the rest of the write proceeds.
- **Read-only trusted-path tables.** History/events and agent-proposal/checkpoint tables are
  sync-*down* only. A client write targeting them is refused, so a client (or a compromised client)
  cannot forge history or fabricate proposals; only trusted server/worker paths write them.
- **Identity forced and immutable.** On every create/update the server overwrites the owner with the
  authenticated session's owner and treats the owner as immutable on update; the write is
  additionally scoped to the owner's own rows.
- **Cross-owner operations are silent no-ops, not errors.** A write that does not match the owner
  filter simply affects **zero rows**. Throwing on mismatch was rejected deliberately: an error would
  roll back the entire upload batch and wedge the sync retry loop (the failure mode behind an earlier
  "confirm reverts itself" bug). The security guarantee stays *structural* — a client can never
  overwrite or delete a row it does not own — without making sync brittle. A genuinely unknown table
  is the one case that does raise.
- **Incoming changes are DTOs.** The client sends operation envelopes (create / update / delete with
  an id and a data payload); the server sanitises each payload against the allowlist before it
  touches storage. The wire shape is decoupled from the storage schema.
- **Early-return guards.** Unauthenticated requests, malformed identifiers, invalid statuses or risk
  levels, oversized payloads, non-pending proposal re-decisions, invalid handoff modes/unbounded
  instructions, out-of-range confidence (must be within 0–1), and attachment previews failing
  type/encoded-prefix/size checks are all rejected up front, before any work.

### 3.7 Per-user isolation, revocable sessions, least privilege

Defence is layered, with the datastore as the final boundary:

- **Per-user isolation at the data boundary.** Owner foreign keys plus per-user sync filtering
  (`WHERE owner_id = <authenticated owner>`) mean isolation does not depend on application-layer
  checks alone; even a logic bug cannot cross users at the storage layer.
- **Revocable, opaque sessions.** Sessions are opaque and revocable; stored session material is
  non-recoverable (hashed) and carries an expiry. Sign-out and credential recovery revoke or rotate
  sessions immediately.
- **Short-lived sync credentials from a long-lived session.** Clients never embed durable secrets. A
  revocable session mints short-lived, narrowly-scoped sync credentials; the sync layer does *not*
  use the master session directly, and revoking or modifying the parent session invalidates the
  derived sync credential.
- **Least privilege and anti-enumeration.** Sensitive authentication paths return generic failures
  (no account enumeration), throttle repeated attempts *before* expensive verification, and gate
  optional flows behind explicit configuration. Additive factors (passwordless / second factor /
  delegated sign-in) layer on without changing the revocable-session backbone. Service roles (API,
  sync, worker, agent) hold least-privilege credentials; automated writes are bounded and
  attributable by service or agent.

### 3.8 Human-in-the-loop durable checkpoints and autonomy classification

The agent runs flows that **interrupt before any risky or external-state-changing step** and persist
a **durable checkpoint** capturing the serialised workflow state, the proposed action's payload, its
provenance, its confidence, and an explicit risk classification (risk level, reversibility, whether
it mutates external state). The flow then routes a proposal/approval card to the triage queue and
**resumes or aborts on the human decision**; approval stores bounded resume data and continues the
workflow, rejection aborts and runs cleanup, and completion or failure is recorded back into the
item's history. Because checkpoints are durable and the claim is atomic (§3.5), an approval survives
restarts and an attempt executes at most once.

The **autonomy / risk taxonomy** governs what may happen without asking:

- **Context / read** — gather information, search personal context, summarise, classify, or propose.
  May run automatically; results are reviewable evidence.
- **Low-risk, reversible action** — limited blast radius, safely undoable. May auto-execute *only*
  when the autonomy policy allows, still recording evidence.
- **Medium-risk** — could affect external state, time, money, relationships, or user-visible
  commitments. Requires explicit approval.
- **High-risk / irreversible** — requires explicit approval and may demand stronger confirmation,
  richer provenance, or a deliberate manual handoff.

**Structure is always confirmed**, at every level — autonomy may advance *work*, but never bypasses
the human's authorship of an item's structure.

### 3.9 Provenance and confidence on proposals

Every proposal — capture suggestion, enrichment, email extraction, agent research, completion
detection — carries **provenance** (its source category and, where possible, a verbatim source
quote) and a **confidence** value constrained to the 0–1 range at the data boundary. This is what
makes the confirm gate fast rather than burdensome: the user sees *why* something was proposed and
*how sure* the system is, and can accept with one gesture or correct inline. On the card, a source
quote (for example, the email sentence that implied the task) is rendered in the distinct
machine-proposed visual voice so it is instantly legible as system evidence requiring validation.
Provenance and confidence are first-class, validated fields — not free-text decoration. Proposal
decisions are durable and single-use: accepting or rejecting a pending proposal atomically locks it
so duplicate clicks, retries, or sync repeats cannot reapply the same decision, and decisions linked
to a checkpoint move that checkpoint consistently.

### 3.10 The client repository and sync contracts

Clients never scatter raw writes through UI code; they go through a single **repository** that
centralises lifecycle operations and keeps invariants close to the logic. Its behaviours include:
connect / disconnect sync; prepare and clear active-user state; capture a single item; detect and
ingest a nested list; confirm and reject proposals; mark done and reopen; update details; edit due
date and tags; watch the proposed, active, and done lists; watch a single task, its events, and its
descendants / roll-ups; and manage lightweight tags. Surfaces differ in UI while sharing product
behaviour.

The **sync contract** is correspondingly narrow: replicate owner-scoped rows to every authenticated
client; support local-first optimistic writes for tasks, tags, and bounded attachment previews; keep
the proposed / active / done / project-rollup / history views reactive; treat events, proposals, and
checkpoints as trusted-path (sync-down) writes; support account switching without data leakage; and
never expose internal datastore or worker endpoints directly to clients.

### 3.11 Testing posture

Testing is **behavioural and flow-level**, verifying outcomes and contracts at real boundaries
rather than internal wiring, written in **arrange-act-assert** form. Representative cases:

- Arrange an empty local store; **act** by capturing text; **assert** a `proposed` item exists
  immediately with source metadata — even with the network unavailable, and it syncs later.
- Arrange a proposed item with suggestions; act by confirming with edits; assert active status and
  confirmed fields.
- Arrange a proposed item; act by running enrichment; assert only suggestion fields / events /
  proposals changed — and that enrichment against an already-confirmed item is a no-op.
- Arrange a nested list; act by ingesting it; assert parent-child links, source order, and labels;
  assert self-parenting and cycles are rejected.
- Arrange a parent with open and done descendants; act by reading the roll-up; assert correct counts
  without duplicated or mutated child history.
- Arrange two owners; act with each syncing and writing; assert no cross-owner rows ever appear, and
  that a cross-owner write is a silent no-op rather than a batch failure.
- Arrange duplicate or case-varied tags; act by normalising/renaming; assert one logical label.
- Arrange an agent attempt request; act by processing it; assert a pending approval checkpoint
  *before* any external mutation, and that replaying the operation produces no duplicates and an
  approved attempt executes at most once.
- Arrange a pending proposal; act by accepting it twice; assert the first succeeds and the second is
  not reapplied.

Mocking is reserved for hard external edges (third-party personal-context sources, the language
model, the executor on user hardware); the core data and sync paths are exercised against real
boundaries, because production behaviour — not theoretical correctness — is the source of truth.

### 3.12 Non-goals

Capture is **single-account-first** (multi-user is supported structurally but is not a launch
focus). It is not a team-collaboration suite, not a calendar/email replacement, and not an
automation platform that acts without review. Autonomy is intentionally bounded: there is **no path
by which software saves a real todo, or takes a consequential action, without a human decision.**
