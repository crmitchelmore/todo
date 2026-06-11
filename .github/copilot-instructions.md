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
- When changing Capture UI, check Mac, iOS, and web parity together: preserve the same capabilities and design grammar while respecting each platform's HIG/native interaction patterns.
- Auth and code-entry screens must remain keyboard-safe on iOS and mobile web; client settings should expose enough version/sync diagnostics to identify stale installs or endpoint mismatches.

## Local Mac app refresh

- Before validating or dogfooding the Mac app on this machine, run `scripts/refresh-mac-app.sh`.
- After committing and pushing changes that affect the macOS app, run `scripts/refresh-mac-app.sh`.
- The script pulls/rebases, builds, moves old `/Applications` and `~/Applications` Capture bundles to `/tmp/todo/capture-mac-old-installs/<timestamp>/`, installs `/Applications/CaptureMac.app`, and launches it.
- Do not manually delete old app installs; move them aside or use the script.

## UI validation loop

- After UI changes, run `scripts/ui-validate.sh web ios mac` or the narrow affected surface, then inspect the generated `.ui-artifacts/<timestamp>/design-review.md` checklist and screenshots/logs.
- Use Playwright/Webwright for browser interaction, iOS Simulator for iOS, and the built Mac app screenshot/log path for macOS. Fix usability/design issues before claiming parity.

## PowerSync/Railway rollouts

- Schema changes that sync to clients must be rolled out across every layer together: Postgres migration/publication, PowerSync sync rules, backend upload allow-list, and web/Swift local schemas.
- Deploy Railway services from the repository root; only use service-specific paths where existing scripts document them.
- Railway deploy path exception: deploy `backend` and `powersync` from the repository root, but deploy `worker` with `scripts/with-secrets.sh railway up ./worker --path-as-root --ci --service worker` because Railway cannot infer the worker from the monorepo root.
- Do not ship App Store/TestFlight clients with a schema-writing change until the live Railway backend and PowerSync service have been migrated and redeployed.

## Apple signing

- Reuse existing valid Apple signing certificates and provisioning profiles where possible; do not create new certificates/profiles on every release attempt.
- If signing fails due certificate capacity, clean up clearly unused/expired Apple Developer certificates and repair profiles, then rerun the release workflow. Never commit certificates, profiles, Apple passwords, or app-specific passwords.

## OpenClaw executor

- Approved AI attempt checkpoints are executed by the worker only when `OPENCLAW_EXECUTOR_ENABLED=1` and SSH settings are configured; keep production/Railway safe-by-default unless the host can actually reach the Mac Mini.
- The Mac Mini executor target is `bravostation@bravos-mac-mini.taile313a5.ts.net`, workdir `/Users/bravostation/clawd`, CLI `/opt/homebrew/bin/openclaw`, default agent `imessage-agent`, using `openclaw agent --agent imessage-agent --message "$PROMPT" --json --timeout 120`.
- Use non-interactive SSH (`-o BatchMode=yes`) with the private key outside the repo. The current integration public key to authorise on the Mini is `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAB0tzfbA0+aKXye4HItr3TeUCwol4fg2GrOua8F8/Sa capture-openclaw-executor`.
- Do not close OpenClaw execution work until SSH/OpenClaw smoke succeeds and a completed or failed attempt is recorded back into `task_events`.

## Web testing

- On this macOS environment, bundled Playwright Chromium can crash during launch; use system Chrome for Playwright scripts (`p.chromium.launch(channel="chrome", headless=True)`).
