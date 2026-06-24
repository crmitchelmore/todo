-- Capture task automation preferences and synced notification history.
-- Automation is task-scoped and owner-scoped so retries can safely resume without per-client state.

\connect postgres;

alter table public.tasks
  add column if not exists agent_mode text not null default 'research';

alter table public.tasks
  add column if not exists agent_plan_confirmation integer not null default 1;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'tasks_agent_mode_chk'
       and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_agent_mode_chk
      check (agent_mode in ('research', 'attempt'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'tasks_agent_plan_confirmation_chk'
       and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_agent_plan_confirmation_chk
      check (agent_plan_confirmation in (0, 1));
  end if;
end $$;

create table if not exists public.notifications (
  id          uuid primary key,
  owner_id    uuid not null references public.users(id) on delete cascade,
  task_id     uuid,
  kind        text not null,
  severity    text not null default 'info',
  title       text not null,
  body        text,
  metadata    text,
  created_at  timestamptz not null default now(),

  constraint notifications_owner_task_fk
    foreign key (owner_id, task_id)
    references public.tasks(owner_id, id)
    on delete set null,
  constraint notifications_kind_chk
    check (kind in (
      'research_ready',
      'interview_needed',
      'attempt_plan_ready',
      'attempt_started',
      'attempt_completed',
      'attempt_failed'
    )),
  constraint notifications_severity_chk check (severity in ('info', 'success', 'warning', 'error')),
  constraint notifications_title_len_chk check (char_length(title) between 1 and 160),
  constraint notifications_body_len_chk check (body is null or char_length(body) <= 2000),
  constraint notifications_metadata_len_chk check (metadata is null or octet_length(metadata) <= 4096),
  constraint notifications_metadata_json_chk check (metadata is null or jsonb_typeof(metadata::jsonb) is not null)
);

create index if not exists notifications_owner_created_idx
  on public.notifications (owner_id, created_at desc, id desc);
create index if not exists notifications_owner_task_created_idx
  on public.notifications (owner_id, task_id, created_at desc, id desc)
  where task_id is not null;

do $$
begin
  if not exists (
    select 1
      from pg_publication_tables
     where pubname = 'powersync'
       and schemaname = 'public'
       and tablename = 'notifications'
  ) then
    alter publication powersync add table public.notifications;
  end if;
end $$;
