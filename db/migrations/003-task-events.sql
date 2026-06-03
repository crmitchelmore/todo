-- Capture task history / AI work log.
-- Append-only, server-owned events used by the detail pane timeline.

\connect postgres;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'tasks_owner_id_unique'
       and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_owner_id_unique unique (owner_id, id);
  end if;
end $$;

create table if not exists public.task_events (
  id          uuid primary key,
  owner_id    uuid not null,
  task_id     uuid not null,
  actor       text not null,
  event_type  text not null,
  title       text not null,
  body        text,
  metadata    text,
  created_at  timestamptz not null default now(),

  constraint task_events_owner_task_fk
    foreign key (owner_id, task_id)
    references public.tasks(owner_id, id)
    on delete cascade,
  constraint task_events_actor_chk
    check (actor in ('user', 'system', 'worker', 'agent', 'api')),
  constraint task_events_type_chk
    check (event_type in ('captured', 'confirmed', 'updated', 'completed', 'reopened', 'deleted', 'enriched')),
  constraint task_events_title_len_chk check (char_length(title) between 1 and 160),
  constraint task_events_body_len_chk check (body is null or char_length(body) <= 2000),
  constraint task_events_metadata_len_chk check (metadata is null or octet_length(metadata) <= 4096),
  constraint task_events_metadata_json_chk check (metadata is null or jsonb_typeof(metadata::jsonb) is not null)
);

create index if not exists task_events_owner_task_created_idx
  on public.task_events (owner_id, task_id, created_at desc, id desc);

create index if not exists task_events_owner_created_idx
  on public.task_events (owner_id, created_at desc, id desc);

do $$
begin
  if not exists (
    select 1
      from pg_publication_tables
     where pubname = 'powersync'
       and schemaname = 'public'
       and tablename = 'task_events'
  ) then
    alter publication powersync add table public.task_events;
  end if;
end $$;
