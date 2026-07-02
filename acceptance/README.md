# Capture acceptance & eval suite

Repeatable, evidence-producing acceptance tests for the **web, macOS, and iOS** Capture apps,
driven through [use.computer](https://use.computer) sandboxes against **production Railway**, plus
**LLM-as-judge evals** for the non-deterministic agentic steps.

Tracked in beads under epic `cap-rdr`. Feature source-of-truth: [`features/`](features/).

## What it verifies

| Suite | Driver | What it proves | Model key needed? |
|-------|--------|----------------|-------------------|
| `api` | backend REST | capture→proposed, confirm→active, reject→cancelled, idempotency, agent-handoff `202`, proposal-decision validation, auth 401, owner-scoping | no |
| `web` | Safari in a macOS sandbox | sign-in → capture → confirm card → confirm→active → reject→cancelled → settings, with screenshots + server cross-checks | no |
| `sync` | API + Safari sandbox | PowerSync propagation both directions (API→web down-sync, web→server up-sync) | no |
| `evals` | worker prompt code + LLM judge | quality of auto-research briefs, interview prompts, enrichment suggestions (rubrics in `features/agentic.md`) | **yes** (skips w/o) |
| `mac` | macOS sandbox | build → upload → launch CaptureMac → sign in → capture → confirm (screenshots) | no |
| `ios` | iOS simulator sandbox | build → install → launch CaptureiOS → capture → confirm (screenshots) | no |

## Prerequisites

1. `cp .env.acceptance.example .env.acceptance` and fill it (the file is git-ignored).
   - `USE_COMPUTER_API_KEY` — required for the sandbox-driven suites (`web`, `sync`, `mac`, `ios`).
   - `ACCEPTANCE_LLM_API_KEY` (+ `_BASE_URL`, `_MODEL`) — enables the `evals` quality judging and
     the model-config acceptance. **Any OpenAI-compatible endpoint.** Without it those parts SKIP.
   - `ACCEPTANCE_ACCOUNT_EMAIL`/`_PASSWORD` — leave blank to auto-generate a stable dedicated
     throwaway account (owner-scoped; never touches real data). Persisted back into `.env.acceptance`.
2. `npm install`

## Run

```bash
npm run test          # deterministic API acceptance (fast, no sandbox)
npx tsx run.ts all    # api + web + sync + evals (+ mac/ios if built)
npx tsx run.ts web    # just the web scenario
npm run evals         # LLM-as-judge evals (skips w/o ACCEPTANCE_LLM_*)
npx tsx src/harness/smoke.ts   # verify the use.computer key + a sandbox boot
```

Every sandbox suite writes screenshots + `report.md`/`report.json` under `reports/<suite>-<ts>/`.

## Design notes (why it's built this way)

- **Web is served locally inside the sandbox.** The web app is built once with the production
  backend/PowerSync baked in, uploaded to the sandbox, and served on `localhost` for Safari to
  drive. This is deliberate: the shipped Railway web edge intermittently returns `upstream error`
  / a blank `#root`, which made direct driving flaky. Serving the same build locally is repeatable
  and still exercises the **real production backend + PowerSync**, so sync is genuinely tested.
  (The Railway web-edge flakiness is itself a finding — see the run summary / `cap-rdr`.)
- **DOM-level driving, not pixels.** Safari's web content is not exposed in the accessibility tree,
  so the driver injects JavaScript via `osascript … do JavaScript` (file-based, no shell-quoting
  hazards) to click by visible text/selector and read state. Robust against layout shifts.
- **Deterministic vs LLM-gated split.** Exact outcomes (status transitions, counts, event kinds)
  are asserted directly. Non-deterministic agent output (research/interview/enrichment) is graded
  by an LLM judge against explicit rubrics; those parts skip cleanly when no model key is set.
- **Evals drive the real worker code.** `evals/run.ts` imports the worker's actual prompt builders
  (`runAgentResearch`, `interviewPromptFor`, `enrich`) so it measures shipping behaviour, not a copy.
- **Secrets** live only in the git-ignored `.env.acceptance`; tokens are redacted from all logs/reports.

## Layout

```
features/            deep-searched feature inventory (web / native / agentic) — the spec
src/harness/         env, use.computer client, Safari DOM driver, backend API client, report, LLM judge
scenarios/           web.ts, sync.ts, mac.ts, ios.ts   (one sandbox, many steps, one report)
tests/api.test.ts    deterministic backend acceptance (node:test)
evals/run.ts         LLM-as-judge evals over the real worker prompt code
run.ts               orchestrator
reports/             screenshots + report.md/json (git-ignored)
```
