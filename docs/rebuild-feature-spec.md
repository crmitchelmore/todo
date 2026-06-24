# Capture rebuild feature specification

## 1. High-level overview

Capture is a fast-capture, AI-organised, agent-backed task system for a user who wants to record work instantly, have software organise it, and stay in control before anything becomes a real todo.

The product intent is simple:

1. Capture a thought from any surface without friction.
2. Suggest useful structure immediately.
3. Enrich the item later with personal context and agent research.
4. Ask the human to confirm the structure.
5. Sync the confirmed task everywhere.
6. Allow bounded automation only when it is safe, observable, and reversible enough.

The rebuild should preserve the product's conceptual integrity: Capture is not a generic project manager with AI bolted on. It is an instant inbox, confirmation workflow, personal-context organiser, and agent workbench built around the principle that the human decides what becomes durable task state.

The philosophy is simple - speed, automation and delight.

Design wise, the vision is omnifocus but for AI in 2030.

### Supported surfaces

The product must support three primary user-facing platforms:

| Surface | Role |
| --- | --- |
| Mobile app | Fast personal capture, share-sheet capture, voice/shortcut-style capture, widgets, and review on the move. |
| Desktop app | Fast keyboard-driven capture, menu-bar/global-hotkey capture, detail review, and local integration with a trusted always-on machine. |
| Web app | Universal access, sign-in, task review, settings, and a platform-neutral fallback UI. |

All surfaces must share the same task model, sync model, authentication model, and confirmation semantics.

### Generic hosting shape

The hosted system should be described and rebuilt as a small client-server stack:

| Plane | Generic responsibility |
| --- | --- |
| Client plane | Local-first apps that capture instantly and sync in the background. |
| API plane | Authentication, owner-scoped writes, capture ingestion, agent approval decisions, and public client configuration. |
| Sync plane | Account-agnostic cross-device sync over a durable source-of-truth database. |
| Data plane | A managed relational datastore with constraints, ownership boundaries, task history, and indexed read paths. |
| Worker/agent plane | Background enrichment, context discovery, proposal creation, and approval-gated automation. |

The rebuilt system may use any equivalent managed hosting provider, container host, or private server arrangement. The required property is not a specific vendor or framework; it is that clients only need stable public endpoints for API and sync, while the datastore and worker processes remain internal and protected.

### Design philosophies

The rebuild must follow these philosophies:

| Philosophy | Product meaning |
| --- | --- |
| Conceptual Integrity | Every surface must feel like the same product: instant capture, proposed state, human confirmation, then synced task. |
| Design for Production / Stability | Durable state must be owner-scoped, constrained, idempotent, observable, and safe under retries. |
| Outcome Over Output | The goal is captured, organised, confirmed tasks and safer execution, not simply generating AI suggestions. |
| Human-Centred Design | The human remains in control; AI and agents propose, explain provenance, and wait for confirmation where appropriate. |

### Adopted architecture patterns

Use these patterns as rebuild constraints, not optional style preferences:

| Pattern | Requirement |
| --- | --- |
| Modular monolith | Keep the backend as a cohesive product backend with clear internal modules rather than many premature services. |
| Client-server | Clients talk to narrow API/sync boundaries; they do not reach into internal services. |
| Layered architecture | Separate presentation, domain lifecycle, repository/data access, background work, and external integrations. |
| Repository | Centralise task lifecycle writes behind a task store/repository abstraction on every client. |
| Materialised view | Parent/project screens should read rolled-up child progress and recent history instead of mutating child records into parent summaries. |
| Idempotency | Repeated capture, enrichment, handoff, and decision attempts must be safe. |
| Data Transfer Object | Cross-boundary payloads should be typed DTOs with bounded fields. |
| Guard clause | Validate and reject invalid inputs early at boundaries. |
| Arrange-Act-Assert | Tests should describe behaviour through setup, action, and observable outcome. |

## 2. Medium-detail product and architecture

### Core user journeys

#### Instant capture

The user can capture a raw thought from mobile, desktop, web, share-like extension points, shortcut-like entry points, widgets, a desktop hotkey, or pasted markdown lists.

Capture must:

1. Trim and preserve the user's intent.
2. Write a local proposed item immediately.
3. Never wait for network, sync, remote AI, or agent work.
4. Return control to the user immediately.
5. Attach small image previews where supplied.
6. Queue out-of-process captures durably if the network or API is unavailable.

#### Suggest and enrich

Every captured item receives an immediate local suggestion. This suggestion should include, where detectable:

- due date/time;
- category;
- confidence;
- suggestion source.

A background worker may later upgrade those suggestion fields using richer parsing, historical category hints, personal context, web context, location context, or an AI model.

Background enrichment must never silently turn a proposal into an active todo and must never overwrite the human-confirmed task fields. It can update suggestion fields, append history, and create pending agent proposals.

#### Confirm before save

The confirm card is the core interaction.

Every proposed item must be shown with:

- title;
- suggested due date;
- suggested category;
- tags;
- priority where available;
- notes or source context where available;
- confidence and provenance for AI/agent-derived data;
- accept, edit, and reject actions.

Only after confirmation does a task become active. Rejection removes or cancels the proposal according to the chosen implementation, but rejected proposals must not appear as active todos.

#### Work the task

Active tasks support:

- edit title, notes, category, tags, priority, and due date;
- mark done;
- reopen;
- attach image previews;
- view task history;
- request agent research;
- request an agent attempt, gated by approval where the action is consequential.

#### Projects and recursive subtasks

Projects are ordinary tasks with child tasks. Do not introduce a separate canonical project entity.

Requirements:

1. A task may have a parent task owned by the same user.
2. Child tasks may themselves have children.
3. Direct self-parenting is invalid.
4. Cycles are invalid.
5. Nested markdown ingestion must preserve hierarchy.
6. Parent views must roll up child progress and recent child events.
7. Rolling up child state must not duplicate or mutate child history.
8. Tags remain lightweight labels, not the hierarchy model.

#### Personal context and integrations

The product should be able to enrich tasks from personal context sources:

- local notes or knowledge vault;
- email;
- calendar availability;
- web search or web lookup;
- location context.

Integration outputs are proposals or history, not silent task mutations. The user must be shown source quotes, confidence, and provenance when a personal-context source influenced a suggestion.

#### Agentic discovery and execution

An always-on private agent process may research or attempt tasks.

The agent model is:

1. User requests research or an attempt from a task.
2. The backend records an idempotent handoff event.
3. A worker or agent claims the request.
4. The agent discovers context and prepares a proposal.
5. Low-risk read/context actions may run automatically.
6. Medium-risk, high-risk, irreversible, or external-state-mutating actions require explicit approval.
7. The decision is recorded and can resume or abort the agent workflow.
8. All results are visible as task history and/or agent proposals.

### Lifecycle model

The canonical task lifecycle is:

```text
raw capture -> proposed -> active -> done
                         \-> cancelled
```

Interpretation:

| State | Meaning |
| --- | --- |
| proposed | Captured or generated item awaiting human confirmation. Not yet a real todo. |
| active | Human-confirmed todo. Appears in the main active list. |
| done | Completed todo. Appears in recent/completed views. |
| cancelled | Explicitly discarded or cancelled item. Does not appear as active work. |

The important invariant is that only the human confirmation path promotes proposed work into active work.

### Data ownership and sync

The system is multi-user, even if initially used by one person.

Requirements:

1. Every durable row that belongs to a user must include an owner identifier.
2. The database must enforce ownership relationships with constraints, not only application code.
3. Sync must filter rows by authenticated owner.
4. Server-side write handling must force ownership from the authenticated session rather than trusting client-submitted ownership.
5. Signing out or switching accounts must clear local optimistic data so one account cannot replay or display another account's pending writes.
6. Clients must not embed secrets.

### Security and authentication

The rebuild must support:

- account registration;
- sign-in;
- logout/session revocation;
- passwordless or second-factor flows as additive enhancements;
- short-lived sync credentials minted from a revocable session;
- generic failure responses for sensitive authentication paths to reduce account enumeration;
- throttling of repeated credential attempts before expensive verification work;
- recovery paths that revoke or rotate compromised credentials.

Sessions should be opaque and revocable. Stored session material should be hashed or otherwise non-recoverable.

### Durable-state safety

The datastore is a safety boundary.

Durable state must enforce:

- owner foreign keys;
- task hierarchy constraints;
- bounded text and structured payload sizes;
- proposal status values;
- task event actor and event type values;
- attachment type and size limits;
- confidence values between 0 and 1;
- indexed owner-scoped lookup paths;
- append-only history for task events.

Any automation-accessible write must be idempotent, auditable, bounded in scope, and attributable to a service, user, or agent operation.

### User experience principles

The UI should optimise for speed and trust:

1. Capture fields are always obvious and keyboard-friendly.
2. Confirmation takes one keystroke, click, tap, or swipe in the common case.
3. Proposed, active, and done lists are visually distinct.
4. Suggested structure is editable inline.
5. AI/agent provenance is visible without overwhelming the user.
6. Mobile layouts must avoid horizontal scrolling and collapsed primary controls.
7. Desktop capture must be accessible without switching context.
8. Web must remain a complete functional surface, not just an admin panel.

## 3. Specific rebuild requirements

### Domain entities

#### User

Represents an account that owns all user data.

Required fields:

- id;
- email where available;
- password or credential hash where applicable;
- created timestamp.

Relationships:

- one user has many sessions;
- one user has many tasks;
- one user has many tags;
- one user has many agent proposals and checkpoints.

#### Session

Represents a revocable authenticated client session.

Required fields:

- id;
- user id;
- token hash;
- client metadata;
- created timestamp;
- expiry timestamp;
- last-seen timestamp;
- revoked timestamp.

#### Task

Represents both todos and projects.

Required fields:

- id;
- owner id;
- parent task id, nullable;
- title;
- notes, nullable;
- status;
- category, nullable;
- tags as an ordered list of names;
- due timestamp, nullable;
- priority, nullable;
- suggested due timestamp, nullable;
- suggested category, nullable;
- suggestion confidence, nullable;
- suggestion source, nullable;
- source, nullable;
- created timestamp;
- updated timestamp;
- confirmed timestamp, nullable;
- completed timestamp, nullable.

Rules:

1. Title must be non-empty after trimming when a task is stored.
2. Status must be one of proposed, active, done, or cancelled.
3. Priority, when present, must be within a small bounded range.
4. Suggested fields are advisory until confirmation.
5. Parent task, when present, must belong to the same owner.
6. A task cannot be its own parent.
7. A task hierarchy cannot contain cycles.

#### Tag

Represents a user-managed lightweight label.

Required fields:

- id;
- owner id;
- name;
- colour;
- created timestamp;
- updated timestamp.

Rules:

1. Tag identity is case-insensitive name per owner.
2. Tag names are trimmed.
3. Empty tag names are invalid.
4. New tags may be auto-created during capture or confirmation.
5. Renaming a tag updates task tag lists.
6. Renaming into an existing tag merges the labels.

#### Task event

Represents append-only history and agent/worker activity for a task.

Required fields:

- id;
- owner id;
- task id;
- actor;
- event type;
- title;
- body, nullable;
- metadata, nullable structured object;
- created timestamp.

Allowed actors:

- user;
- system;
- worker;
- agent;
- API.

Required event categories:

- captured;
- confirmed;
- updated;
- completed;
- reopened;
- deleted or cancelled;
- enriched;
- agent requested;
- agent completed;
- agent failed.

Task events must be readable by clients and written by trusted server/worker paths.

#### Task attachment

Represents synced attachment metadata and small previews.

Required fields:

- id;
- owner id;
- task id;
- filename, nullable;
- media type;
- byte size;
- preview data;
- created timestamp.

Rules:

1. Only image preview types are accepted.
2. Preview payloads must be size-bounded.
3. Attachments belong to a task and owner.
4. Full external blob storage can be added later; the base rebuild only requires small synced previews.

#### Agent proposal

Represents something an agent or worker asks the user to accept or reject.

Required fields:

- id;
- owner id;
- task id, nullable;
- proposal type;
- status;
- title;
- body, nullable;
- payload, nullable structured object;
- provenance, nullable structured object;
- confidence, nullable;
- source;
- created timestamp;
- updated timestamp;
- decided timestamp, nullable;
- applied timestamp, nullable.

Proposal types:

- create task;
- update task;
- complete task;
- action.

Proposal statuses:

- pending;
- accepted;
- rejected;
- cancelled;
- expired.

Rules:

1. Payload and provenance must be bounded and valid structured data when present.
2. Confidence must be between 0 and 1 when present.
3. Pending proposals may be decided once.
4. Accepted/rejected decisions must update linked checkpoints where applicable.

#### Agent checkpoint

Represents a human approval gate for an agent workflow.

Required fields:

- id;
- owner id;
- task id, nullable;
- proposal id, nullable;
- thread id;
- checkpoint key;
- interrupt-before label;
- action type;
- risk level;
- status;
- action payload;
- resume payload, nullable;
- created timestamp;
- updated timestamp;
- decided timestamp, nullable;
- resumed timestamp, nullable.

Risk levels:

- low;
- medium;
- high.

Statuses:

- waiting;
- approved;
- rejected;
- resumed;
- cancelled.

Rules:

1. One owner/thread/checkpoint key combination is unique.
2. Low-risk read/context actions may skip checkpoint creation.
3. External state mutation, irreversible work, and high-risk actions require approval.

### Required flows

#### Capture flow

```text
User enters raw text or shares content
-> client creates stable capture id
-> client inserts local task with status proposed
-> client runs cheap local suggestion
-> sync uploads owner-scoped row
-> worker may upgrade suggestion fields
-> confirm card updates live
```

Acceptance criteria:

1. Capturing a normal task returns immediately without remote dependency.
2. Capturing while offline creates or preserves a durable local/outbox record.
3. A captured row starts as proposed.
4. Proposed rows appear in the proposed inbox on every synced surface.
5. Enrichment can update suggestion fields but not status, title, due date, or confirmed category.

#### Confirmation flow

```text
User reviews proposed item
-> accepts as-is or edits structure
-> system promotes item to active
-> confirmed timestamp is set
-> updated timestamp is set
-> tags are normalised/materialised
```

Acceptance criteria:

1. A proposed item cannot become active without a confirmation action.
2. Edits made on the confirm card become the real task fields.
3. Suggested fields remain distinguishable from confirmed fields.
4. Rejecting a proposal prevents it appearing as active work.

#### Completion flow

```text
User marks active task done
-> status becomes done
-> completed timestamp is set
-> task remains available in recent done/history views
```

Acceptance criteria:

1. Completing a task does not delete it.
2. Reopening restores active status and clears or supersedes completion state according to a single documented rule.
3. Parent rollups reflect child completion without changing child events.

#### Markdown list ingestion flow

```text
User pastes list
-> parser recognises markdown bullets, numbered items, and checkboxes
-> indentation becomes parent-child relationships
-> inline tags become task tags
-> ancestor titles may be added as compatibility tags
-> unchecked/plain items become proposed
-> checked items may import as done
```

Acceptance criteria:

1. Prose with one stray dash is not exploded into multiple tasks.
2. Nested list structure is preserved.
3. Empty list items are ignored.
4. Done checkboxes import as completed work.
5. Imported tasks retain owner scope and source metadata.

#### Enrichment flow

```text
Worker polls proposed tasks needing richer suggestions
-> learns from user's recent confirmed/done categories
-> computes richer due/category/priority/tag suggestions
-> patches only suggestion fields
-> appends an enrichment event
-> optionally creates pending agent proposal
-> optionally performs context discovery
```

Acceptance criteria:

1. Worker ticks do not overlap for the same process.
2. Enrichment is safe to retry.
3. Duplicate events/proposals are prevented with deterministic ids or equivalent idempotency keys.
4. Failed enrichment is logged and does not corrupt task state.
5. Worker never promotes proposed tasks.

#### Agent handoff flow

```text
User requests research or attempt on a task
-> API validates mode and bounded instructions
-> API records an idempotent request event
-> worker/agent processes request
-> context discovery result is written to history/proposals
-> attempt mode creates approval gate before external action
```

Acceptance criteria:

1. Repeated handoff requests within a short retry window resolve to the same logical request.
2. Invalid mode or oversized instructions are rejected or bounded.
3. Research produces visible history/proposal output.
4. Attempt mode cannot mutate external state before approval.

#### Agent proposal decision flow

```text
User accepts or rejects pending proposal
-> API locks proposal
-> if pending, marks accepted/rejected
-> linked waiting checkpoint is approved/rejected
-> optional resume payload is stored within size limit
```

Acceptance criteria:

1. Non-pending proposals cannot be decided again.
2. A decision is owner-scoped.
3. Linked checkpoints move consistently with proposal decision.
4. Resume payloads are structured and bounded.

### API boundary

Expose a narrow API surface. Specific paths can vary, but the capabilities must exist:

| Capability | Requirement |
| --- | --- |
| Health | Lightweight liveness/readiness response for the API. |
| Register | Create an account and session. |
| Login | Exchange credentials for a session without leaking whether the email exists. |
| Logout | Revoke the current session. |
| Token for sync | Mint a short-lived owner-scoped sync credential. |
| Public signing keys/config | Let the sync service verify short-lived credentials. |
| Client write batch | Apply only allowlisted table/column mutations, forced to the authenticated owner. |
| Capture ingestion | Accept out-of-process captures with a client-generated idempotency key. |
| Agent handoff | Queue research/attempt requests for a task. |
| Agent proposal decision | Accept or reject pending proposals. |
| Auth recovery/MFA | Support additive passwordless, recovery, and second-factor operations. |

Guard clauses should reject unauthenticated, malformed, oversized, or cross-owner requests early.

### Client repository/task store contract

Every client should use a task store or repository abstraction rather than scattering raw data writes through UI code.

Required methods or equivalent behaviours:

- connect/disconnect sync;
- prepare for active user;
- clear local data on sign-out;
- capture single item;
- detect and capture markdown list;
- confirm proposal;
- reject proposal;
- mark done/reopen;
- update task details;
- set due date;
- set tags;
- watch proposed tasks;
- watch active tasks;
- watch done tasks;
- watch one task;
- watch task events;
- watch task and descendant events;
- watch task and descendant attachments;
- watch child rollup;
- create/rename/recolour/delete tags.

### Sync contract

The sync system must:

1. Replicate owner-scoped rows to every authenticated client.
2. Support local-first optimistic writes for tasks, tags, and small attachments.
3. Treat task events and agent proposals as server/worker-owned from the client perspective.
4. Keep proposed, active, and done lists reactive.
5. Support account switching without data leakage.
6. Avoid exposing internal worker/datastore endpoints directly to clients.

### Hosting and operations requirements

The production deployment should satisfy:

1. Clients reach only public API and sync endpoints over encrypted transport.
2. Data and worker services communicate privately.
3. Runtime secrets are provided through the host's secret mechanism, not committed files.
4. The worker can run either in the hosted environment or on a trusted private machine connected to the same backend.
5. Background workers have bounded batch size and poll intervals.
6. Query/write activity from automation is attributable through logs or events.
7. The same stack can run locally for development with equivalent service boundaries.

### Defensive database requirements

Because this is a durable, agent-accessible system, do not rely on careful callers.

Required safeguards:

- least-privilege database roles for API, sync, worker, and any agent process where practical;
- statement and idle transaction timeouts for automation roles;
- separate connection pools for user API paths and background/agent work where load warrants it;
- short transactions with no network, AI, user-interaction, or long file work inside them;
- parameterised queries;
- indexes matching owner/status/task/history access paths;
- row-count and payload-size bounds on automated writes;
- append-only events for high-value state transitions;
- clear distinction between "no result" and query/permission/timeout failure;
- slow-query, timeout, retry, and write-count observability by service/operation.

### Non-goals for the rebuild

The first rebuild should not:

- replace the task hierarchy with a separate project table;
- treat tags as the canonical project model;
- allow AI or workers to promote proposed tasks to active tasks;
- allow agents to perform consequential external actions without approval;
- expose raw internal datastore access to clients;
- hard-code a single hosting vendor, sync vendor, UI framework, or database product into the product specification;
- block capture on remote AI, network, or background worker completion.

### Behavioural acceptance test suite

Use behavioural tests over implementation micro-tests. Suggested coverage:

1. **Capture is instant and proposed:** arrange an empty local store, act by capturing text, assert a proposed item exists immediately with source metadata.
2. **Confirm promotes:** arrange a proposed item with suggestions, act by confirming with edits, assert active status and confirmed fields.
3. **Worker cannot promote:** arrange a proposed item, act by running enrichment, assert only suggestion fields/history/proposals changed.
4. **Markdown hierarchy:** arrange a nested markdown list, act by batch capture, assert parent-child links and tags.
5. **Owner isolation:** arrange two users, act with each syncing/writing, assert no cross-user rows appear.
6. **Tag normalisation:** arrange duplicate/case-varied tags, act by capture and rename, assert one logical tag and rewritten task references.
7. **Agent approval gate:** arrange an attempt request, act by worker processing, assert a pending proposal/checkpoint before external mutation.
8. **Proposal decision idempotency:** arrange a pending proposal, act by accepting twice, assert first succeeds and second is not re-applied.
9. **Offline outbox:** arrange unavailable API, act by out-of-process capture, assert durable queued capture and later drain.
10. **Parent rollup:** arrange a parent with open/done descendants, act by reading rollup, assert counts without duplicate child history.

### Rebuild completion definition

A rebuild is acceptable when:

1. Mobile, desktop, and web surfaces can all sign in to the same account.
2. Capture works offline-first and syncs when connectivity returns.
3. Proposed items require confirmation before becoming active.
4. Background enrichment updates suggestions without mutating confirmed fields.
5. Recursive subtasks and parent rollups work.
6. Tags remain lightweight labels.
7. Agent proposals and approval gates are visible and decidable.
8. Data ownership is enforced at the datastore and sync boundaries.
9. The system can run locally and in production-like hosting with the same service boundaries.
10. Behavioural tests cover the core lifecycle, ownership, hierarchy, enrichment, and approval invariants.
