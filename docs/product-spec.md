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
and, for low-risk reversible work, optionally act — and it can propose how an item is structured,
when to schedule it, and when it looks done — but it always returns results as proposals you
approve. You own one set of todos, synced across every surface.

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
   exposed no further than each integration needs. AI assistance is opt-in, personal data is not
   used to train shared models, and the data-retention posture of any model provider is explicit.

### 2.3 The key features and how they relate

The features are not a list; they are a single flow with a few orthogonal capabilities hanging
off it.

- **Capture → suggest → enrich → confirm → sync** is the spine.
  - *Capture* is one instant local write at status `proposed`. It never waits on network, sync, a
    model, a date parser, or an agent.
  - *Suggest* is an immediate on-device guess (a due date and a category) that patches the item
    with no network round-trip, so the confirm card is useful right away — even offline.
  - *Enrich* is a richer background pass (broader categories, urgency, fuller date / deadline /
    recurrence parsing, a duration estimate, tags, priority, project hints, personal-context
    discovery) that patches the **same** item again. Every suggestion it writes carries its own
    confidence and provenance, and is conditioned on the user's own confirmed history so guesses
    feel personal rather than generic.
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
- **Completion detection.** A signal from any source — an email reply that reads as "done", an
  agent observation, a connected tool changing state — can produce a *proposal* to mark an item
  complete, never an automatic completion. Each signal is one cited, confidence-scored proposal that
  re-enters the same confirm gate.
- **Rich, intent-revealing structure.** A task is more than a title and a due date. It can carry a
  start/defer date (hide until), a due date (when you plan to work on it), a hard deadline (when it
  must be done), a deliberate "today / committed" flag, a duration estimate, a priority, a recurrence
  rule, blocking/related dependencies, and reminders. Every one of these can be *suggested* by
  enrichment and is *confirmed* (or edited) by the human — structure is never silently imposed.
- **AI decomposition.** For a large item, the agent can propose a set of subtasks (or turn a pasted
  outline into a tree). Each proposed child enters the triage queue, so an AI plan still becomes real
  work only by human confirmation.
- **Scheduling proposals.** The agent can propose *where* work lands — time-blocks across the day or
  week — using the calendar-feasibility evidence the system already computes, plus the duration,
  deadline, priority, earliest-start, and an optional "ideal-week" template. It can warn that a
  deadline is at risk or that a day is over-committed. Crucially this is **propose-then-confirm, not
  auto-pilot**: the human approves, edits, or rejects; nothing is written to the calendar silently.
- **Edit / merge proposals.** When automation would change an *existing* confirmed field, a note, or
  an external item — not just create a new one — it surfaces a before/after diff for approval.
  Confirm-before-save thus extends to **confirm-before-change**, so agents can tidy and update
  without silently rewriting your data.

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
  desktop hotkey, a system share action, voice/shortcut entry (with an accept / refine / reject pass
  on the transcription), widgets, the web, paste-a-list, an email-forwarding address, a browser
  clipper that grabs the page and selection, context-autofill from the foreground app, and the agent
  itself as a text/message delegate — all funnel into the same single write. Clients render optimistic
  state and sync in the background.
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
- **Confirm before change.** Automation that alters existing confirmed structure, a note, or an
  external item shows a before/after diff and waits for approval — the change-time counterpart of
  confirm-before-save. Approvals, reminders, and at-risk warnings can be actioned (accept / reject /
  snooze) directly from a notification, without opening the app.
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

**Active work has sub-states orthogonal to the gate.** Within `active`, a task may be flagged
*in-progress* or *blocked / on-hold* (for example, waiting on a dependency). These describe how the
work is going, not whether it is real; they never substitute for — or bypass — the
proposed→confirmed gate, and the active outline and roll-ups read them to show what is moving and
what is stuck.

**Recurring tasks spawn forward, never mutate the past.** A confirmed task may carry a recurrence
rule and an anchor — repeat on a fixed schedule, or repeat from the date it was completed. When such
a task is completed, the system spawns the next occurrence as a **new** row at `confirmed` status
(the human already approved the pattern; re-confirming every occurrence would flood the triage
queue), inheriting structure and linked to the completed instance for lineage. The completed row
stays immutable, so each occurrence keeps its own audit trail. Enrichment may *suggest* a recurrence
rule on capture, but it becomes canonical only once confirmed.

**Complication resolved — enrichment must write continuously without ever advancing an item.**
Enrichment and agents need to keep improving a `proposed` item (better date, category, tags,
research notes) while never promoting it. The enrichment write is therefore scoped two ways: it may
touch only suggestion fields, *and* only while the row is still `proposed`. Concretely the
background update both restricts the columns it sets and guards its filter on `status = 'proposed'`,
so a confirmation that races ahead simply causes the enrichment write to affect zero rows. Status
changes have exactly one author: the human. Transitions append **semantic events** (captured,
confirmed, updated, enriched, scheduled, rescheduled, blocked, unblocked, recurrence-spawned,
agent-requested, agent-completed, agent-failed, completed, reopened, rejected, cancelled), and the
history surfaces meaning first, raw detail second.

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

**Concurrency choice — per-field last-write-wins, with set-valued fields handled additively.** The
default is **per-field last-write-wins**: every write carries only the columns it actually changed,
so two devices editing *different* fields of the same task — one edits the title while the agent
patches a suggestion — never clobber each other; only a genuine same-field race resolves
last-write-wins. This is the safe realisation of the same simple philosophy — avoid a heavyweight
merge engine until evidence demands it — and it is the sync layer's own default, but it only holds
if the write path patches changed columns rather than replacing the whole row, so a naive whole-row
write is explicitly disallowed. Two further rules remove the remaining silent-loss traps:

- **Set-valued fields are additive, not overwritten.** Tags (and similar sets) live as their own
  owner-scoped rows with a unique key and insert-on-conflict-do-nothing, giving *add-wins* semantics:
  a tag added on one device and a different tag added on another both survive. Serialising such a set
  into a single value would let one device's write erase the other's.
- **Status only advances; it never regresses.** The write handler enforces the lifecycle as a state
  machine, so a late-arriving enrichment or agent write can never pull a `confirmed` / `done` item
  back to `proposed`. This is the write-time guarantee behind §3.1's invariant.

We explicitly recorded the heavier alternative — a field-level conflict-free merge for long-form text,
so two offline edits to the *same* note both survive — and the trigger to adopt it: *only if*
concurrent editing of the same long text becomes common, applied selectively to that field rather
than the whole model. Wall-clock tie-breaking is imperfect under clock skew; it is acceptable for
this single-user, few-devices-plus-one-agent workload and revisited if evidence says otherwise.

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
- **Typed relations beyond hierarchy.** Besides parent/child, tasks may carry typed links —
  *blocking / blocked-by*, *related*, *precedes / follows* — and an *earliest-start* date. These are
  owner-scoped and pass the same self-reference and cycle guards, so the dependency graph, like the
  project tree, can never close into a ring or cross owners. Dependencies let the active outline mark
  work *blocked* (§3.1) and let scheduling respect ordering (§3.13).

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

**Proposal types share one gate.** Everything enrichment or the agent emits is one of a small set of
proposal types — a *suggestion* (a suggested field), a *decomposition* (subtasks), a *schedule*
(proposed time-blocks), an *edit / merge* (a diff against an existing field, note, or external item),
a *completion signal*, or a consequential *action*. All carry confidence and provenance and pass the
confirm/approval gate; an *edit / merge* additionally renders a before/after diff, so changing
existing data is as reviewable as creating a new item. New proposal types must reuse this one gate
rather than opening a side-channel.

### 3.9 Provenance and confidence on proposals

Every suggestion and proposal — an on-device guess, a background enrichment, an email extraction,
agent research, a schedule, an edit/merge, a completion signal — carries **provenance** (its source
category and, where possible, a verbatim source quote) and a **confidence** value constrained to the
0–1 range at the data boundary. This is what
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
ingest a nested list; confirm and reject proposals; mark done and reopen; update details; set the
dates (start / due / deadline), a recurrence rule, a duration estimate, and priority; toggle the
today/committed flag; manage tags, relations, and reminders; request a decomposition or a schedule
proposal and decide it; decide an edit/merge proposal; watch the proposed, active, done, today,
upcoming/scheduled, and blocked lists; and watch a single task, its events, and its descendants /
roll-ups. Surfaces differ in UI while sharing product behaviour.

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
- Arrange a confirmed recurring task; act by completing it; assert a new `confirmed` occurrence is
  spawned, linked to the now-immutable completed row, with its own fresh history.
- Arrange one task; act by editing different fields on two offline devices; assert both edits survive
  after sync (per-field, not whole-row, last-write-wins).
- Arrange one task; act by adding a different tag on two offline devices; assert both tags survive
  (add-wins set).
- Arrange a `confirmed` task; act by replaying a late enrichment or agent write; assert status cannot
  regress to `proposed`.
- Arrange a schedule or edit/merge proposal; act by leaving it pending; assert no calendar write and
  no change to the existing field occur until the human approves.

Mocking is reserved for hard external edges (third-party personal-context sources, the language
model, the executor on user hardware); the core data and sync paths are exercised against real
boundaries, because production behaviour — not theoretical correctness — is the source of truth.

### 3.12 The richer task model: dates, recurrence, dependencies

Capture's task carries more intent-revealing structure than a title and a single date. Every field
below is suggestible by enrichment and confirmed (or edited) by the human, is owner-scoped, and sits
on the write-path allowlist (§3.6); none is set silently.

**Dates serve different questions.** Four distinct date concepts replace a single "due":

- *start / defer* — the task is hidden from active views until this date, so work surfaces when it
  can begin rather than adding noise earlier.
- *due* — when you plan to work on it; drives gentle overdue signalling and is the usual recurrence
  anchor.
- *deadline* — a hard external cut-off, distinct from due; rendered with its own emphasis and
  escalating reminders, and never silently moved by automation.
- *committed / today* — a deliberate, human-only flag meaning "I will work on this today," separate
  from "due today." The **Today** view is the union of committed items and items whose start / due /
  deadline has arrived, so a curated focus list is never just mechanical date-matching.

**Recurrence is a rule plus an anchor.** A recurring task stores a recurrence rule (an established
calendar-recurrence format) and an anchor — *repeat on schedule* (next occurrence computed from the
original date) or *repeat from completion* (next computed from when it was actually finished) —
optionally bounded by an end date or a count. Completion spawns the next occurrence forward as a new
confirmed row (§3.1), preserving per-occurrence history.

**Dependencies and ordering.** Typed relations (§3.4) — blocking / blocked-by, related, precedes /
follows — plus an *earliest-start* date let work be marked *blocked* and let the scheduler respect
ordering. The dependency graph reuses the same owner-scoping and cycle guards as the project tree.

**Effort and priority.** A *duration estimate* (and accumulated *time spent*) and a small *priority*
scale make the active outline and scheduling meaningful. Enrichment can propose a duration from the
title and the user's own history of similar tasks; the human confirms.

**Set-valued fields stay additive.** Tags and reminders are their own rows, not serialised blobs
(§3.3), so concurrent additions never silently overwrite one another.

### 3.13 Scheduling: propose-then-confirm time-blocking

Scheduling is where Capture's "agent proposes, human disposes" stance pays off most. The system
already scores calendar *feasibility* for a date (is there a clear focus window before it?); a
schedule proposal extends that into *placing* work — without ever writing to the calendar by itself.

**Inputs.** A schedule proposal reads the duration estimate, due vs hard deadline, priority,
earliest-start and dependencies, the user's working hours and an optional *ideal-week template*
(which kinds of work belong in which windows — deep work mornings, admin late Friday), existing busy
time, and buffer / travel allowances.

**Output is a proposal, not an action.** The agent returns a set of proposed time-blocks carrying the
feasibility evidence and a confidence; the human approves, edits, or rejects them through the same
confirm card and proposal / checkpoint machinery (§3.8, §3.9). Nothing lands on the calendar
silently; a consequential external write still passes the approval gate.

**Warnings are proposals too.** When projected completion slips past a deadline the agent raises an
*at-risk* warning early (not just an overdue flag); when a day exceeds its planned capacity it raises
an *over-commitment* warning offering to push lower-priority work. When a scheduled block is missed,
named actions — reschedule, complete-and-add-time, split-and-reschedule — let the human re-plan in
one gesture.

**Routines.** Recurring routines (§3.12) can be scheduled with flexible windows ("most mornings,
flexible") and a weekly focus-time target that the scheduler defends by moving — not dropping — the
block when conflicts appear.

### 3.14 Delivery: actionable notifications and reminders

Decisions and reminders must reach the user wherever they are and be actionable without opening the
app — otherwise the confirm gate becomes friction.

**Reminders** can be absolute, relative to a due or start date, or location-based (on arriving at or
leaving a place), and attach as their own rows so a task can carry several. Location reminders reuse
the location integration and the same privacy posture (§2.2).

**Approval delivery.** A proposal or approval can be delivered as an *actionable notification* whose
buttons map to the confirm gate — accept / reject / snooze — so the human can dispose of it from the
lock screen or a glance. The action is recorded through the normal idempotent, single-use proposal
decision path (§3.9), so a tap from a notification and a tap in the app cannot double-apply. A missed
notification never loses the decision: the item simply remains in the triage queue.

**Ambiguous or missing input.** When a date (or other suggested field) cannot be parsed confidently,
enrichment does not guess silently: it either leaves the field unset for the human to add at the
confirm card, or surfaces a low-confidence suggestion clearly marked as such. Capture-first speed is
never sacrificed to resolve an ambiguity — the item is already safely captured.

### 3.15 Non-goals

Capture is **single-account-first** (multi-user is supported structurally but is not a launch
focus). It is not a team-collaboration suite, not a calendar/email replacement, and not an
automation platform that acts without review. Autonomy is intentionally bounded: there is **no path
by which software saves a real todo, or takes a consequential action, without a human decision.**
