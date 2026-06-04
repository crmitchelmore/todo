# Capture agent instructions

## Task/project model

- Treat projects as ordinary tasks with recursive subtasks via `tasks.parent_task_id`; do not reintroduce project-as-tag as the canonical model.
- Tags remain lightweight labels. Ancestor titles may be compatibility tags during markdown ingestion, but hierarchy is canonical.
- Markdown list ingestion must preserve nesting as parent-child task relationships.
- Parent task views should roll up child progress and recent child `task_events` without duplicating or mutating child history.

## Local Mac app refresh

- Before validating or dogfooding the Mac app on this machine, run `scripts/refresh-mac-app.sh`.
- After committing and pushing changes that affect the macOS app, run `scripts/refresh-mac-app.sh`.
- The script pulls/rebases, builds, moves old `/Applications` and `~/Applications` Capture bundles to `/tmp/todo/capture-mac-old-installs/<timestamp>/`, installs `/Applications/CaptureMac.app`, and launches it.
- Do not manually delete old app installs; move them aside or use the script.

## PowerSync/Railway rollouts

- Schema changes that sync to clients must be rolled out across every layer together: Postgres migration/publication, PowerSync sync rules, backend upload allow-list, and web/Swift local schemas.
- Deploy Railway services from the repository root; only use service-specific paths where existing scripts document them.
- Do not ship App Store/TestFlight clients with a schema-writing change until the live Railway backend and PowerSync service have been migrated and redeployed.
