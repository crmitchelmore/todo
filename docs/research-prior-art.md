---

# Research Brief: Open-Source Patterns for a Fast-Capture AI Todo System

---

## Area 1 — Self-Hostable Todo & Task Managers with Sync

### 1.1 `go-vikunja/vikunja` ⭐ 4.4k · Go + TypeScript

A full-featured, self-hosted task manager with REST API, CalDAV support, and full web/desktop clients.

**Task model** (from `pkg/models/tasks.go:63-160`): flat relational entity with `ID`, `Title` (TEXT NOT NULL), `Description` (LONGTEXT), `Done`, `DoneAt`, `DueDate`, `StartDate`, `EndDate`, `RepeatAfter` (seconds), `RepeatMode` (default / monthly / from-current-date), `Priority` (bigint), `HexColor`, `PercentDone`, `Labels []Label`, `Assignees []User`, `RelatedTasks`, `Attachments`, `BucketID` (Kanban column), and `Position float64`. Tasks are namespaced under `ProjectID` with a per-project sequential `Index`. The UID field exists for CalDAV but is not exposed over JSON.

**Sync pattern**: Server-authoritative REST API with an xorm ORM → SQLite/MySQL/PostgreSQL. No native CRDT; clients do optimistic updates then reconcile. Supports CalDAV for calendar apps. **Adopt**: the `Task` struct is the most complete open-source task schema we found; clone it as a reference for your data model.

### 1.2 `johannesjo/super-productivity` ⭐ 14k+ · TypeScript (Angular + Electron)

Advanced todo + time-tracking + Pomodoro app with Jira/GitHub/GitLab integrations, available as a web app, desktop, and Android.

**Sync pattern**: Pure local-first; all state lives in IndexedDB via a custom JSON store. Sync is handled by user-configured sync providers (Dropbox, S3, WebDAV, Google Drive) using simple file diffing with a `lastModified` timestamp — not CRDTs. Offline works completely. **Adopt**: their file-based sync approach is easy to bootstrap; their project-structure separation (tasks, projects, tags) is worth studying.

### 1.3 `usememos/memos` ⭐ 40k+ · Go + TypeScript

Lightweight self-hosted note-taking with timeline-first capture UI, REST + gRPC API, and a ~20 MB Docker image on SQLite/MySQL/PostgreSQL.

**Sync pattern**: Server-authoritative. Single Go binary; no native offline/CRDT. REST and gRPC APIs make it very agent-friendly. Notes are Markdown stored as plain text in the DB. **Adopt**: use Memos as inspiration for the *quick-capture UX* (open → type → done) and as the wire protocol reference for a "note → enrichment" pipeline.

### 1.4 `tasks/tasks` ⭐ 3k+ · Kotlin (Android)

The Android tasks app (forked from Astrid), with full support for Google Tasks, CalDAV, EteSync, DAVx5 and iCalendar. Desktop alpha available.

**Sync pattern**: CalDAV / Google Tasks API bidirectional sync with conflict resolution via ETag. Uses Room (SQLite) as local store, syncs via standard calendar protocols. **Adopt**: the iCalendar/CalDAV approach is the most interoperable task exchange format; use it as a secondary sync target to let any CalDAV client read tasks.

---

## Area 2 — Local-First / Offline Sync Engines

### 2.1 `automerge/automerge` ⭐ 16k+ · Rust (core) + JS/WASM + Swift

CRDT library targeting "PostgreSQL for local-first apps". Rust core compiled to WASM for JS and exposed as native Swift via `automerge-swift`.

**How it works**: Text/List/Map CRDTs with a binary sync protocol. Each document is a compressed log of operations; merging is always conflict-free. Includes `automerge-repo` which adds pluggable network (WebSocket, WebRTC) and storage backends.

**Swift**: `automerge/automerge-swift` (SPM package) is the native Swift binding — same CRDT semantics, cross-compatible with JS. `automerge-repo-swift` adds network/storage. The showcase app `automerge/meetingnotes` is a full SwiftUI app demonstrating WebSocket + P2P collaboration.

**Adopt**: **Automerge is the top pick for Swift + Web with one shared data model.** Install `automerge-swift` via SPM; use `automerge-repo` in your web app; encode tasks as Automerge `Map` objects. Binary sync protocol works over any transport (WebSocket, APNS-relayed, iCloud CKAsset).

> `automerge/automerge-swift` — SPM: `https://github.com/automerge/automerge-swift.git`

### 2.2 `yjs/yjs` ⭐ 18k+ · JavaScript/TypeScript

CRDT framework that exposes data as observable shared `Y.Map`, `Y.Array`, `Y.Text`. Extremely fast, network-agnostic, used in production by Evernote, Gitbook, AFFiNE, Huly.

**How it works**: Operation-based CRDT with a binary encoding. Integrates with React, Tiptap/Slate/CodeMirror, SQLite via `y-indexeddb`, Postgres via `y-postgresql`. Sync providers: `y-websocket` (server), `y-webrtc` (P2P), `y-dat`.

**Swift gap**: No native Swift CRDT library for Yjs. You'd need to serialize to binary and handle in JS/WebAssembly. Less ideal than Automerge for the Swift side. **Adopt**: use Yjs for the *web* layer if you need rich-text (notes) collaboration; pair with Automerge for the Swift-native side.

### 2.3 `powersync-ja/powersync-swift` + `powersync-ja/powersync-js` · Swift + TypeScript

**PowerSync** is a SQLite-based sync engine: client-side SQLite (oplog-based) synced against Postgres/MySQL/MongoDB on the server. Has **first-class Swift SDK** (via SPM) and JS SDKs for React Native + Web.

From `powersync-swift` README:
```swift
// Package.swift
.package(url: "https://github.com/powersync-ja/powersync-swift", from: "1.0.0")

let powerSync = PowerSyncDatabase(schema: mySchema)
// Optional: GRDB integration for existing Swift apps
try config.configurePowerSync(schema: mySchema)
let dbPool = try DatabasePool(path: dbPath, configuration: config)
```

Demo apps include a React Native + Supabase todo list and a Swift + Supabase todo list. PowerSync's "sync rules" let you define which rows sync to which users (partial replication).

**Adopt**: **PowerSync is the pragmatic choice** if you want SQL semantics (tasks are rows), existing Swift + React Native SDKs, and self-hostable backend (Docker image). Simpler mental model than CRDTs; conflicts resolved by last-writer-wins per row with server-side override capability.

### 2.4 `Nozbe/WatermelonDB` ⭐ 10k+ · JavaScript/TypeScript

Reactive, lazy-loading SQLite database for React Native + React web. Used in production at Nozbe since 2017.

**How it works**: Observable Model layer over SQLite (native thread on mobile). Sync is bring-your-own server: implement `pullChanges(lastPulledAt)` and `pushChanges(changes)` endpoints. Framework handles the rest including conflict resolution. Web uses IndexedDB. Model defined with `@field`, `@children` decorators.

**Adopt**: Use WatermelonDB as the **React/React Native client layer** when using a custom REST sync backend. Its sync protocol is simple to implement server-side and battle-tested in production todo apps.

---

## Area 3 — Natural Language Date/Task Parsing

### 3.1 `wanasit/chrono` ⭐ 4.5k+ · TypeScript

The de-facto NL date parser in JS/TS. Parses "next Tuesday", "2 weeks from now", "this Friday 13:00-16:00", durations, and relative dates. TypeScript-native with pluggable Parser + Refiner architecture.

```ts
import * as chrono from 'chrono-node';
chrono.parseDate('An appointment on Sep 12-13');
// Supports: forwardDate option, custom timezone mappings, locales (en, fr, ja, nl, ru, uk, vi, de, es...)
chrono.parse('tomorrow at 8pm', new Date(), { forwardDate: true });
```

**Swift gap**: No native Swift port of chrono. You'd run it server-side or in a JS worker. **Adopt**: `npm install chrono-node` — use in your web/RN capture layer and in server-side enrichment. For Swift parsing, invoke via a lightweight HTTP microservice or use `NSDataDetector` as a fallback.

### 3.2 `microsoft/Recognizers-Text` · C#/.NET + TypeScript + Python

Microsoft's production NLP entity extraction used in LUIS, Bot Framework, Power Virtual Agents. Recognizes dates, times, durations, sets (recurrence: "every Monday"), numbers, currencies, in 10+ languages including Chinese, Japanese, Korean, Arabic.

```ts
// npm: @microsoft/recognizers-text-suite
const results = Recognizers.recognizeDateTime(input, Recognizers.Culture.English);
// => [{typeName: "datetimeV2.datetime", resolution: {values: [...]}]
```

Recurrence patterns (e.g. "every first Tuesday of October") are a **key differentiator** over chrono-node. **Adopt**: use Recognizers-Text when you need robust recurrence parsing; chrono-node for simple relative dates.

### 3.3 `facebook/duckling` ⭐ 4.5k+ · Haskell

Haskell-based NL parser that outputs structured JSON. Runs as a microservice. Supports Duration, Time, AmountOfMoney, Distance, etc.

```bash
curl -XPOST http://0.0.0.0:8000/parse \
  --data 'locale=en_GB&text=tomorrow at eight&dims=["time","duration"]'
# => {"value":"2017-10-03T08:00:00","grain":"hour","type":"value"}
```

Used by Meta at scale (powers wit.ai). No native Swift/JS library — it's a service. **Adopt**: run Duckling as a sidecar service for *server-side* enrichment (high accuracy, multi-language, recurrence). Use chrono-node on the client for instant feedback.

### 3.4 Recommendation matrix

| Parser | JS/TS | Swift | Recurrence | Self-hosted | Use case |
|--------|-------|-------|------------|-------------|----------|
| chrono-node | ✅ native | ❌ (NSDataDetector fallback) | ❌ | ✅ | Client-side instant parse |
| MS Recognizers-Text | ✅ npm | ❌ | ✅ strong | ✅ | Server-side, recurrence |
| Duckling | ❌ (HTTP only) | ❌ | ✅ | ✅ docker | Server sidecar |

---

## Area 4 — AI Auto-Categorisation / Auto-Tagging of Tasks & Notes

### 4.1 `instructor-ai/instructor` ⭐ 10k+ · Python

The standard library for structured LLM output. Wraps any provider (OpenAI, Anthropic, Gemini, Ollama) and enforces a Pydantic schema with automatic retries on validation failure.

```python
import instructor
from pydantic import BaseModel, Literal

class TaskEnrichment(BaseModel):
    project: str
    priority: Literal["high", "medium", "low"]
    tags: list[str]
    due_date: str | None
    is_actionable: bool

client = instructor.from_provider("openai/gpt-4o-mini")
result = client.chat.completions.create(
    response_model=TaskEnrichment,
    messages=[{"role": "user", "content": f"Classify this task: {raw_text}"}]
)
# result.project, result.tags are always valid Python objects
```

**Pattern**: define your taxonomy as a `Literal` type; the LLM fills it out. Retries automatically on bad JSON/validation error. Works with local models (Ollama) for on-device enrichment. **Adopt**: this is the cleanest pattern for task enrichment — define `TaskEnrichment` once, call on every capture event.

### 4.2 `agno-agi/agno` (cookbook) · Python

Agno (`agno-agi/agno`) is an agent SDK with a `gmail_action_items.py` cookbook (`cookbook/91_tools/google/gmail_action_items.py`) that demonstrates the exact AI extraction pattern we need:

```python
class ActionItem(BaseModel):
    owner: str
    task: str
    deadline: Optional[str]
    priority: Literal["high", "medium", "low"]
    source_quote: str  # <- provenance for trust

class ThreadActionItems(BaseModel):
    thread_subject: str
    action_items: List[ActionItem]
    summary: str

agent = Agent(
    model=OpenAIChat(id="gpt-4o"),
    tools=[GmailTools()],
    output_schema=ThreadActionItems,   # <- forces structured output
    add_datetime_to_context=True,      # <- agent knows today's date
    instructions=["Extract action items...look for 'can you', 'please', 'I will'..."]
)
```

**Pattern**: LLM + structured output schema + `source_quote` provenance field = explainable classification. **Adopt directly**: this is the reference implementation for email → structured task extraction.

### 4.3 `khoj-ai/khoj` ⭐ 29k+ · Python + TypeScript

Self-hostable personal AI that ingests Obsidian vaults, PDFs, Notion, and more. Runs semantic search over embeddings + LLM chat. Self-hostable on-device with local models.

**Categorisation pattern**: Khoj uses embedding-based semantic search to find related notes, then prompts the LLM to classify/relate new items. No explicit tagger, but the embedding + nearest-neighbor approach naturally surfaces project context without fine-tuning. **Adopt**: Khoj's indexing pipeline (Markdown → chunk → embed → SQLite/PostgreSQL) is the best OSS reference for "context-aware task routing to existing projects."

### 4.4 `bitsofchris/openaugi` · Python

Personal vault-to-agent bridge. Ingests Obsidian vault into SQLite with semantic + graph retrieval, then exposes via MCP server. Uses HDBSCAN clustering to discover knowledge areas automatically.

**Pattern**: `openaugi cluster` runs HDBSCAN at two resolutions (coarse = life areas, fine = specific ideas) over embeddings — this is a label-free auto-categorisation engine. Tags emerge from density clustering rather than LLM prompting. **Adopt**: use HDBSCAN over your task embeddings to bootstrap initial project suggestions without user labels.

---

## Area 5 — Obsidian Integration

### 5.1 `coddingtonbear/obsidian-local-rest-api` · TypeScript (Obsidian plugin)

Exposes a HTTPS REST API (port 27124) + MCP server to your Obsidian vault. Bearer-token authenticated with self-signed cert.

**What it exposes**:
- Full CRUD on any vault file
- Surgical section patching (by heading, block ref, frontmatter key)
- Simple full-text search **and** JsonLogic queries against frontmatter/tags/path
- Periodic notes (daily/weekly/monthly)
- Command palette execution
- Tag listing

```bash
# Read a note
curl -k -H "Authorization: Bearer <key>" https://127.0.0.1:27124/vault/path/to/note.md

# Append to a heading section
curl -k -X PATCH -H "Operation: append" -H "Target-Type: heading" \
  -H "Target: My Section" --data "New task" \
  https://127.0.0.1:27124/vault/note.md
```

**MCP integration**: The plugin includes a built-in MCP server at `https://127.0.0.1:27124/mcp/`. Claude Desktop, Claude Code, and Cursor can all connect directly. **Adopt**: this is the authoritative bridge for agent → Obsidian writes. Use the PATCH endpoint to append extracted tasks back to daily notes.

### 5.2 `obsidian-tasks-group/obsidian-tasks` ⭐ 11k+ · TypeScript (Obsidian plugin)

The standard task management plugin for Obsidian. Tracks tasks across the vault using markdown checkbox syntax with emoji-encoded metadata:

```markdown
- [ ] Remember to do that important thing 📅 2022-12-17
- [ ] Send Kate a birthday card 🔁 every January on the 4th ⏳ 2023-01-04
```

Query syntax in code blocks:
```tasks
not done
due before tomorrow
group by filename
sort by due reverse
limit 100
```

**Format**: Tasks are stored inline as `- [ ] Title 📅 due ⏳ scheduled 🔁 recurrence ✅ done_date`. **Adopt**: parse this format with a regex in your agent to read/write tasks files. Key emojis: `📅` = due, `⏳` = scheduled, `🔁` = recurrence, `✅` = completion date, `⬆️` = high priority, `🔼` = medium, `🔽` = low.

### 5.3 `blacksmithgu/obsidian-dataview` ⭐ 13k+ · TypeScript (Obsidian plugin)

Treats the vault as a queryable database. Supports SQL-like DQL, inline expressions, and a full JS API (`dataviewjs`).

```dataviewjs
// List all incomplete tasks with a due date, sorted
dv.taskList(
  dv.pages().file.tasks
    .where(t => !t.completed && t.due)
    .sort(t => t.due)
);
```

**Metadata model**: Reads YAML frontmatter (`---`) and inline fields (`Key:: Value`). **Adopt**: use the Dataview metadata format as your canonical Obsidian frontmatter schema — frontmatter fields like `project:`, `priority:`, `due:`, `tags:` — since Dataview is installed in ~80% of power-user vaults.

### 5.4 `khoj-ai/khoj` (Obsidian connector)

Khoj has a native Obsidian plugin that indexes the vault and exposes it to its LLM chat. The indexing pipeline (vault → markdown chunks → embeddings → vector DB) is the cleanest OSS reference for semantic vault search from an external agent. **Adopt**: use Khoj's vault ingestion pipeline alongside Local REST API for semantic search queries that REST API search can't handle.

---

## Area 6 — Email-to-Task Extraction

### 6.1 `agno-agi/agno` — Gmail Action Items cookbook

Already documented in Area 4 above. The `cookbook/91_tools/google/gmail_action_items.py` is the definitive OSS reference for Gmail → structured task extraction using the Gmail API OAuth2 flow.

**Key patterns from the code**:
1. **OAuth2 flow**: Google Cloud Console → OAuth credentials → `token.json` cached for reuse (standard `google-auth-oauthlib` pattern)
2. **`get_thread`** not `get_message`: always read full thread for multi-message context
3. **Structured output schema** with `source_quote` for provenance
4. **`add_datetime_to_context=True`**: LLM knows today's date for deadline reasoning
5. **Priority heuristic** baked into instructions: "high if deadline is soon or language is urgent"

**Adopt directly**: the `ThreadActionItems` Pydantic schema is a drop-in reference. For IMAP (non-Gmail), swap `GmailTools()` for `imaplib` + `email` stdlib + the same LLM extraction layer.

### 6.2 `khoj-ai/khoj` — Email & scheduling automation

Khoj includes automated newsletter/email digest functionality and can send smart notifications. Its data ingestion pipeline handles email via plugin connectors. The Khoj source (`src/khoj/processor/`) includes processors for various document formats. **Pattern**: schedule periodic Khoj runs against your inbox index; use its "automations" feature to run prompts on a cron schedule and output to your task store.

### 6.3 Pattern: Rules vs LLM hybrid

Looking across repos, the winning pattern is:
1. **Rule-based pre-filter** (sender whitelist, subject keywords, unread flag) via Gmail API `users.messages.list` with `q=` parameter — cheap, no tokens
2. **LLM extraction** only on filtered messages — use `instructor` + Pydantic schema
3. **Completion detection**: search for "RE:" or "✅ done" in reply subject lines, or use Gmail API label changes (`STARRED`, `IMPORTANT` removal) as weak completion signals

**Gmail API auth pattern** (from agno cookbook):
```python
# GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_PROJECT_ID as env vars
# First run: browser OAuth consent → saves token.json
# Subsequent runs: refresh token silently
```

---

## Area 7 — Agent Frameworks for Autonomous Tasks with Human-in-the-Loop

### 7.1 `langchain-ai/langgraph` · Python + TypeScript

**The reference framework for HITL.** Stateful graph execution with durable checkpointing via any store (SQLite, Postgres, Redis).

**HITL mechanism** (from `libs/langgraph/langgraph/graph/state.py` and test corpus):

```python
from langgraph.graph import StateGraph
from langgraph.checkpoint.sqlite import SqliteSaver

builder = StateGraph(AgentState)
builder.add_node("research", research_fn)
builder.add_node("write_task", write_task_fn)   # <- risky action
builder.add_edge("research", "write_task")

# Compile with interrupt_before the risky node
app = builder.compile(
    checkpointer=SqliteSaver.from_conn_string(":memory:"),
    interrupt_before=["write_task"]   # pauses HERE, serializes state
)

# First invoke: runs up to write_task, then pauses
result = app.invoke({"input": "..."}, {"configurable": {"thread_id": "1"}})
# State is checkpointed. Send to UI for approval.

# Resume after human approval:
app.invoke(None, {"configurable": {"thread_id": "1"}})  # resumes from checkpoint
```

- `interrupt_before=[node_name]` pauses before any named node
- `interrupt_after=[node_name]` pauses after (inspect output)
- State serialized to checkpointer DB — survives process restart
- `get_state(config)` inspects pending state; `update_state(config, values)` edits before resume

**Adopt**: LangGraph's `interrupt_before` pattern is the cleanest OSS approval-gate mechanism. Implement as: agent proposes action → serialise to DB → push to iOS notification → user taps Approve/Reject → resume or abort.

### 7.2 `openai/openai-agents-python` ⭐ 8k+ · Python

Official OpenAI SDK for multi-agent workflows. Lightweight, provider-agnostic.

**HITL mechanism**: The SDK has an explicit `human_in_the_loop` module. The core pattern:

```python
from agents import Agent, Runner
from agents.run import RunConfig

# Agents can be configured with approval_policy on tools:
agent = Agent(
    name="Task Creator",
    instructions="Create tasks from emails. Ask for approval before adding.",
    tools=[create_task_tool],
    # Tool-level approval: tools can be marked as requiring human approval
)
# Runner supports streaming + interrupts at tool call points
result = await Runner.run(agent, input_message, run_config=RunConfig(...))
```

The SDK includes `Sessions` for automatic conversation history across runs, `Tracing` for full observability, and `Guardrails` for input/output validation. **Adopt**: use this for simpler single-agent flows; use LangGraph for complex multi-step workflows needing durable state.

### 7.3 `crewAIInc/crewAI` ⭐ 30k+ · Python

Role-based multi-agent framework. "Crews" define agents with roles/goals/tools; "Flows" are the production event-driven architecture.

**HITL mechanism**: CrewAI has `human_input=True` on individual tasks:

```python
from crewai import Task, Agent, Crew

task = Task(
    description="Draft email reply to {thread}",
    expected_output="Email text",
    agent=email_agent,
    human_input=True   # <- pauses, prompts human in terminal / via callback
)
crew = Crew(agents=[email_agent], tasks=[task])
crew.kickoff(inputs={"thread": thread_content})
```

With `human_input=True`, CrewAI calls `input()` (or a registered callback) before accepting the task's output. For async/web use, register a custom `human_input_handler` callback. **Adopt**: use CrewAI if you want a higher-level "crew of specialists" model (e.g. Researcher + Classifier + Task Writer agents with clear separation).

### 7.4 `microsoft/taskweaver` ⭐ 13k+ · Python

Code-first agent framework; each agent step produces and executes Python code. Preserves both chat history AND code execution history (including in-memory DataFrames). Ideal for data-heavy tasks.

**HITL**: TaskWeaver supports "human-in-the-loop" via the Planner role: the Planner agent requests confirmation before executing a CodeInterpreter step. The `ask_human` tool can be registered to pause mid-plan. **Adopt**: use TaskWeaver when task enrichment involves data transformation (e.g. parsing CSV exports of tasks, bulk recategorisation) — its code execution approach beats prompt-only for structured data.

---

## Summary: Recommended Stack per Sub-Problem

| Sub-problem | Recommended OSS pattern |
|---|---|
| **Task data model** | `go-vikunja/vikunja` `pkg/models/tasks.go` as schema reference |
| **Sync (Swift + Web)** | `automerge/automerge-swift` + `automerge-repo` for CRDT; **or** `powersync-ja/powersync-swift` for SQL-native |
| **Sync (React/RN web)** | `Nozbe/WatermelonDB` with custom pull/push endpoints |
| **NL date parsing (client)** | `wanasit/chrono` (JS/TS) + `NSDataDetector` (Swift fallback) |
| **NL date parsing (server, recurrence)** | `microsoft/Recognizers-Text` npm package |
| **AI task classification** | `instructor-ai/instructor` + Pydantic schema |
| **Obsidian read/write** | `coddingtonbear/obsidian-local-rest-api` REST + MCP server |
| **Obsidian task format** | `obsidian-tasks-group/obsidian-tasks` emoji format + `blacksmithgu/obsidian-dataview` frontmatter schema |
| **Vault semantic search** | `bitsofchris/openaugi` (SQLite graph + HDBSCAN clustering) |
| **Email → task extraction** | `agno-agi/agno` cookbook pattern: OAuth2 → `get_thread` → Pydantic structured output |
| **Agent HITL approval gates** | `langchain-ai/langgraph` `interrupt_before=[node]` + `SqliteSaver` checkpointer |
| **Higher-level multi-agent** | `crewAIInc/crewAI` with `human_input=True` per task |
| **Quick-capture UX reference** | `usememos/memos` (timeline-first, single binary) |

---

## Gaps & Uncertainties

1. **CRDT Swift + iCloud sync**: Automerge-swift is the only CRDT with native Swift support, but iCloud CloudKit transport integration is not yet built into `automerge-repo-swift` — you'd need to write a CloudKit sync provider (reading Automerge binary blobs as `CKAsset`). Worth checking `automerge/automerge-repo-swift` directly for latest transport plugins.

2. **PowerSync vs Automerge choice**: PowerSync (SQL rows, last-write-wins) is operationally simpler; Automerge (CRDTs, merge-always) is more correct for offline-first. The right choice depends on whether tasks can be edited simultaneously on two devices — if yes, Automerge; if eventual-consistency is fine, PowerSync.

3. **AI auto-categorisation OSS**: There's no standalone, well-starred "auto-categorise tasks" library — it's a pattern implemented in-app using Instructor/Pydantic. The `bitsofchris/openaugi` HDBSCAN clustering is the only label-free approach I verified.

4. **Email completion detection**: No OSS library specifically detects "task completed via email reply" — this is an unsolved problem. The best available pattern (not found in a single repo) is: check for `RE:` replies with positive sentiment + Gmail label changes.

5. **Focalboard**: `mattermost/focalboard` is **no longer maintained** (unmaintained warning on repo). Do not use as a reference.

6. **LangGraph HITL docs path**: The docs at `langchain-ai/langgraph` are structured differently than expected — I confirmed the `interrupt_before` pattern via the test files (`test_large_cases.py`, `test_pregel.py`) rather than documentation pages.