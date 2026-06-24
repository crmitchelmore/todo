# Capture agent instructions

## Task/project model

- Treat projects as ordinary tasks with recursive subtasks via `tasks.parent_task_id`; do not reintroduce project-as-tag as the canonical model.
- Tags remain lightweight labels. Ancestor titles may be compatibility tags during markdown ingestion, but hierarchy is canonical.
- Markdown list ingestion must preserve nesting as parent-child task relationships.
- Parent task views should roll up child progress and recent child `task_events` without duplicating or mutating child history.

## Conformance profile

- Follow the repository conformance profile when planning, implementing, and reviewing changes.
- Optimise for Conceptual Integrity, Production/Stability, Outcome Over Output, and Human-Centred Design.
- Prefer the existing Modular Monolith, Client-Server, Layered Architecture, Repository, Materialized View, Idempotency, DTO, Guard Clause, and Arrange-Act-Assert patterns where they fit.
- Reuse the canonical homes instead of adding parallel implementations: task lifecycle state machine in `clients/CaptureCore/Sources/CaptureCore/TaskStore.swift`, backend write allowlist in `backend/src/index.ts`, and background enrichment worker in `worker/src/index.ts`.

## UX patterns

- Follow `docs/capture-ux-patterns.md` for product grammar, layout, and visual decisions.
- Amber is reserved for human decisions; iris/purple is for AI evidence; mint is for completion/sync.
- Mac, web, and iOS should keep the same command-deck / triage-queue / active-outline / inspector-card-stack model while using platform-native controls.

## Local Mac app refresh

- Before validating or dogfooding the Mac app on this machine, run `scripts/refresh-mac-app.sh`.
- After committing and pushing changes that affect the macOS app, run `scripts/refresh-mac-app.sh`.
- The script pulls/rebases, builds, moves old `/Applications` and `~/Applications` Capture bundles to `/tmp/todo/capture-mac-old-installs/<timestamp>/`, installs `/Applications/CaptureMac.app`, and launches it.
- Do not manually delete old app installs; move them aside or use the script.

## PowerSync/Railway rollouts

- Schema changes that sync to clients must be rolled out across every layer together: Postgres migration/publication, PowerSync sync rules, backend upload allow-list, and web/Swift local schemas.
- Deploy Railway services from the repository root; only use service-specific paths where existing scripts document them.
- Do not ship App Store/TestFlight clients with a schema-writing change until the live Railway backend and PowerSync service have been migrated and redeployed.

## OpenClaw executor

- Approved AI attempt checkpoints are executed by the worker only when `OPENCLAW_EXECUTOR_ENABLED=1` and SSH settings are configured; keep production/Railway safe-by-default unless the host can actually reach the Mac Mini.
- The Mac Mini executor target is `bravostation@bravos-mac-mini.taile313a5.ts.net`, workdir `/Users/bravostation/clawd`, CLI `/opt/homebrew/bin/openclaw`, default agent `imessage-agent`, using `openclaw agent --agent imessage-agent --message "$PROMPT" --json --timeout 120`.
- Use non-interactive SSH (`-o BatchMode=yes`) with the private key outside the repo. The current integration public key to authorise on the Mini is `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAB0tzfbA0+aKXye4HItr3TeUCwol4fg2GrOua8F8/Sa capture-openclaw-executor`.
- Do not close OpenClaw execution work until SSH/OpenClaw smoke succeeds and a completed or failed attempt is recorded back into `task_events`.

## Web testing

- On this macOS environment, bundled Playwright Chromium can crash during launch; use system Chrome for Playwright scripts (`p.chromium.launch(channel="chrome", headless=True)`).

## UI validation

- Never report a UI change as done from code inspection alone. After any UI change, run `scripts/ui-validate.sh <web|ios|mac>` (or `all`) and inspect the screenshots/logs in `.ui-artifacts/<timestamp>/`. See `docs/ui-validation.md` for the build → screenshot/inspect → fix → rerun loop and the MCP stack (Playwright, XcodeBuildMCP, ios-simulator, peekaboo).
- Explicitly verify the layout is responsive: panels must use the full available width and adapt when the window is resized or goes full-screen — fixed/collapsed panels and wasted right-hand space are recurring regressions on Mac.
- For the web auth gate, confirm email/password fields are visible, editable, non-collapsed, and console-clean on desktop and mobile widths.

## Cross-platform parity

- Task lifecycle and behaviour changes (accept, reject, category assignment, sync) must be implemented in shared `clients/CaptureCore` and applied to every client surface — Mac, iOS, and web (`web/src`) — not just the one in front of you.
- After such a change, verify the behaviour on all three surfaces (e.g. an accepted item leaves the confirm list and a rejected item disappears consistently) before closing the work.

## AI action verification

- For AI/LLM actions (e.g. research hand-off), confirm the worker/LLM actually executed and wrote results back to `task_events` via the worker — check worker logs / the database. Do not treat the feature as working because a UI placeholder or prompt template was attached to the item; that is the symptom of a non-wired action, not success.

## Local data & sync resilience

- Unconfirmed and other local items must survive app update and restart; never let an update or relaunch drop locally captured items.
- Sync must re-establish automatically after an app upgrade with no manual resync step. Treat "had to resync after updating" as a bug.

## Task tracking (beads)

- This project tracks all work with `bd` (beads); `AGENTS.md` and `CLAUDE.md` are the source of truth. Use `bd ready` / `bd show <id>` / `bd update <id> --claim` / `bd close <id>` — do not use markdown TODO lists or other task trackers. Run `bd prime` for full workflow context.
- Work is not complete until quality gates pass and changes are pushed: `git pull --rebase`, `bd dolt push`, `git push`, and `git status` shows the branch up to date with origin.
