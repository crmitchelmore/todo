-- Capture agent proposal queue.
-- Server/agent-owned proposals sync to clients and link to existing confirm-card tasks.

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

create table if not exists public.agent_proposals (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references public.users(id) on delete cascade,
  task_id       uuid,
  proposal_type text not null,
  status        text not null default 'pending',
  title         text not null,
  body          text,
  payload       text,
  provenance    text,
  confidence    double precision,
  source        text not null default 'agent',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  decided_at    timestamptz,
  applied_at    timestamptz,

  constraint agent_proposals_owner_task_fk
    foreign key (owner_id, task_id)
    references public.tasks(owner_id, id)
    on delete set null (task_id),
  constraint agent_proposals_type_chk
    check (proposal_type in ('task_create', 'task_update', 'task_complete', 'action')),
  constraint agent_proposals_status_chk
    check (status in ('pending', 'accepted', 'rejected', 'cancelled', 'expired')),
  constraint agent_proposals_title_len_chk check (char_length(title) between 1 and 160),
  constraint agent_proposals_body_len_chk check (body is null or char_length(body) <= 2000),
  constraint agent_proposals_payload_len_chk check (payload is null or octet_length(payload) <= 8192),
  constraint agent_proposals_payload_json_chk check (payload is null or jsonb_typeof(payload::jsonb) is not null),
  constraint agent_proposals_provenance_len_chk check (provenance is null or octet_length(provenance) <= 4096),
  constraint agent_proposals_provenance_json_chk check (provenance is null or jsonb_typeof(provenance::jsonb) is not null),
  constraint agent_proposals_confidence_chk check (confidence is null or (confidence >= 0 and confidence <= 1))
);

create index if not exists agent_proposals_owner_status_created_idx
  on public.agent_proposals (owner_id, status, created_at desc, id desc);
create index if not exists agent_proposals_owner_task_status_idx
  on public.agent_proposals (owner_id, task_id, status)
  where task_id is not null;

do $$
begin
  if not exists (
    select 1
      from pg_publication_tables
     where pubname = 'powersync'
       and schemaname = 'public'
       and tablename = 'agent_proposals'
  ) then
    alter publication powersync add table public.agent_proposals;
  end if;
end $$;
