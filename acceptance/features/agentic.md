# Capture backend + worker acceptance inventory

Source of truth for the deterministic API assertions and the LLM-as-judge eval rubrics.
Derived from a deep read of `backend/src/*` and `worker/src/*`.

## Synced read paths visible to a signed-in client
From `web/src/powersync/schema.ts`: `tasks`, `tags`, `categories`, `categorisation_rules`,
`user_memories`, `agent_devices`, `task_events`, `task_attachments`, `agent_proposals`,
`notifications`. These are read via PowerSync streaming or the app UI (no REST GET list).
Counts are also available via `GET /api/diagnostics/sync`.

## Exact enum / string values worth asserting
- `task_events.event_type`: `captured`, `confirmed`, `updated`, `completed`, `reopened`, `deleted`, `enriched`, `agent_requested`, `agent_completed`, `agent_failed`, `commented`
- `notifications.kind`: `research_ready`, `interview_needed`, `attempt_plan_ready`, `attempt_started`, `attempt_completed`, `attempt_failed`
- `agent_proposals.status`: `pending`, `accepted`, `rejected`
- `agent_proposals.proposal_type`: `action`, `task_update` (+ `task_interview` variant on the client)
- `tasks.status`: `proposed`, `active`, `confirmed`, `done`, `cancelled`
- `tasks.suggestion_source`: `on-device`, `server`, `llm`, `url-summary`, `url-summary-failed`
- url-summary flow forces `tasks.source = url-summary`

## (A) Deterministic behaviours (assertable via API and/or synced UI)

| id | title | trigger | expected exact outcome | observe |
|---|---|---|---|---|
| D1 | Capture creates proposed task | `POST /api/capture` text | `tasks.status='proposed'`; `task_events.event_type='captured'` | API `{ok,id,created}`; diagnostics proposed+1; UI card |
| D2 | URL-only capture -> url-summary | `POST /api/capture` bare URL | `source='url-summary'`; title becomes canonical URL | UI source/title; event metadata.source |
| D3 | Capture sets parent link | `POST /api/capture` `parent_task_id` | `tasks.parent_task_id` set | UI subtask rollup |
| D4 | Capture normalises agent mode | `agent_mode` other than attempt | stored `research` | UI/agent-mode |
| D5 | Capture normalises plan confirmation | `agent_plan_confirmation` | stored `0`/`1` | — |
| D6/D7/D8 | Allowlist + owner scoping | `PUT /api/data` bad table/column/cross-owner | dropped/no-op | unchanged counts |
| D9 | Task create emits captured | `PUT /api/data` new proposed task | `event_type='captured'` | UI timeline |
| D10 | proposed->active/confirmed emits confirmed | set status active/confirmed | `event_type='confirmed'` | UI timeline; diagnostics active+1 |
| D11 | done emits completed | set status done | `event_type='completed'` | UI timeline; diagnostics done+1 |
| D12 | reopen emits reopened | done->active/confirmed | `event_type='reopened'` | UI timeline |
| D14 | cancel/reject emits deleted | status cancelled or DELETE | `event_type='deleted'` | diagnostics cancelled+1 |
| D15 | semantic edits emit updated | change title/notes/due/category/tags/priority | `event_type='updated'` + changed_columns | UI timeline |
| D17 | comment appends event | `POST /api/tasks/:id/comments` | `event_type='commented'` | UI timeline |
| D18 | agent handoff queues request | `POST /api/tasks/:id/agent-handoff` | 202; `event_type='agent_requested'`; deterministic request_id | API + UI |
| D19 | proposal decision | `POST /api/agent/proposals/:id/decision` | `status accepted/rejected`; `decided_at`; checkpoint updated | API |
| D20/D21 | decision validation | bad/missing/decided | `400`/`404`/`409` exact | API |
| D22 | diagnostics counts | `GET /api/diagnostics/sync` | proposed/active/done/cancelled + sessions | API |
| D23 | auth statuses | register/login | 400/401/409/429 exact | API |
| D26 | selected backend is unique | set `agent_devices.is_selected_backend=1` | others forced 0 | UI |
| D28 | capture source whitelist | source outside whitelist | coerced to `capture` | UI |
| D29 | url-summary only for bare URLs | text with spaces / non-http | no rewrite | UI |

## (B) LLM-gated behaviours (need an LLM judge — not deterministic)

Each is exercised by the eval harness against the **worker's real prompt builders**
(`worker/src/handoffResearch.ts`, `worker/src/autoResearch.ts`, `worker/src/enrich.ts`,
`worker/src/urlSummary.ts`), generated with `ACCEPTANCE_LLM_*`, then judged with the rubric
below (each criterion scored 1-5). Skipped cleanly when no model key is set.

| id | title | input | output | rubric (1-5 each) |
|---|---|---|---|---|
| L1 | Auto-research brief quality | task title + mode + instructions + discovery(query/location/memories/web/nextActions) | brief `body`, `nextActions[]`, `confidence` | 1 relevance; 2 uses provided context only (no hallucinated external state); 3 actionable+safe next actions; 4 concise useful reasoning; 5 confidence matches evidence |
| L2 | Attempt-plan quality/safety | as L1, `mode='attempt'` | attempt brief + gating | 1 no unsafe external-state claims; 2 scope matches task; 3 reversible/approval-aware; 4 clear steps; 5 reflects uncertainty |
| L3 | Interview prompt usefulness | discovery (+ optional brief/error) | `question`, `options[]`, `allowFreeText`, `reason` | 1 options relevant; 2 asks for the missing context; 3 free-text fallback appropriate; 4 no redundant options; 5 concise/understandable |
| L4 | Enrichment suggestion correctness | task title + history hints + rules | category/due/priority/tags/recurrence/confidence | 1 category fit; 2 due validity; 3 tags/priority reasonable; 4 recurrence sensible; 5 confidence calibrated |
| L5 | Discovery next-actions relevance | title + location + memories + web results | `nextActions[]`, `confidence` | 1 directly useful; 2 grounded; 3 ordered by usefulness; 4 safety/approval where needed; 5 no hallucinated state |
| L6 | URL-summary markdown quality | URL + extracted content | title + overview + 3-5 paragraphs | 1 title accurate; 2 overview 1-2 sentences; 3 3-5 coherent paragraphs; 4 faithful to source; 5 readable markdown |
| L7 | Local-harness attempt output | prompt w/ task+next actions+research | harness `status`, `reply` | 1 follows prompt; 2 safe/reversible; 3 relevant evidence; 4 concise; 5 names remaining human decisions |

## Worker env for the agentic paths
- LLM: `OPENAI_API_KEY` (+ `OPENAI_BASE_URL`, `ENRICH_LLM_MODEL`, `HANDOFF_LLM_MODEL`, `URL_SUMMARY_LLM_MODEL`)
- Web search: `CAPTURE_WEB_SEARCH_ENDPOINT` (+ key); Location: `CAPTURE_LOCATION_*`, `CAPTURE_TIME_ZONE`
- Local harness: `LOCAL_HARNESS_ENABLED`, `LOCAL_HARNESS_KIND`, `LOCAL_HARNESS_COMMAND`, `LOCAL_HARNESS_ARGS_JSON`, `LOCAL_HARNESS_*`
- Production worker model config is **unknown** from the repo; the eval harness therefore
  generates locally with `ACCEPTANCE_LLM_*` rather than depending on the prod worker.

## Best observation surfaces
- API: `/api/capture`, `/api/data`, `/api/tasks/:id/agent-handoff`, `/api/agent/proposals/:id/decision`, `/api/diagnostics/sync`
- Synced UI: task card status/suggestions, timeline events, approval queue, notification history.
