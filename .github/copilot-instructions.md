# Capture agent instructions

## Task/project model

- Treat projects as ordinary tasks with recursive subtasks via `tasks.parent_task_id`; do not reintroduce project-as-tag as the canonical model.
- Tags remain lightweight labels. Ancestor titles may be compatibility tags during markdown ingestion, but hierarchy is canonical.
- Markdown list ingestion must preserve nesting as parent-child task relationships.
- Parent task views should roll up child progress and recent child `task_events` without duplicating or mutating child history.

## Local Mac app refresh

- Before validating or dogfooding the Mac app on this machine, run `scripts/refresh-mac-app.sh`.
- The script pulls/rebases, builds, moves old `/Applications` and `~/Applications` Capture bundles to `/tmp/todo/...`, installs `/Applications/CaptureMac.app`, and launches it.
