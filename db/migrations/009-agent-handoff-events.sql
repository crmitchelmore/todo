-- User-requested AI handoff loop events.
-- Additive: expands the task_events type constraint so handoff requests/results can be
-- represented in the existing append-only synced history stream.

\connect postgres;

alter table public.task_events
  drop constraint if exists task_events_type_chk;

alter table public.task_events
  add constraint task_events_type_chk
  check (event_type in (
    'captured',
    'confirmed',
    'updated',
    'completed',
    'reopened',
    'deleted',
    'enriched',
    'agent_requested',
    'agent_completed',
    'agent_failed'
  ));

create index if not exists task_events_agent_requests_idx
  on public.task_events (created_at asc, owner_id, task_id)
  where event_type = 'agent_requested';

create index if not exists task_events_agent_results_request_idx
  on public.task_events (owner_id, task_id, ((metadata::jsonb ->> 'request_id')))
  where event_type in ('agent_completed', 'agent_failed') and metadata is not null;
