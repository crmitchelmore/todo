-- Capture agent HITL checkpoints.
-- Server/agent-owned pause points for consequential actions; not synced to clients directly.

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

create table if not exists public.agent_checkpoints (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references public.users(id) on delete cascade,
  task_id          uuid,
  proposal_id      uuid references public.agent_proposals(id) on delete set null,
  thread_id        text not null,
  checkpoint_key   text not null,
  interrupt_before text not null,
  action_type      text not null,
  risk_level       text not null,
  status           text not null default 'waiting',
  action_payload   text not null,
  resume_payload   text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  decided_at       timestamptz,
  resumed_at       timestamptz,

  constraint agent_checkpoints_owner_task_fk
    foreign key (owner_id, task_id)
    references public.tasks(owner_id, id)
    on delete set null (task_id),
  constraint agent_checkpoints_owner_thread_key_unique
    unique (owner_id, thread_id, checkpoint_key),
  constraint agent_checkpoints_status_chk
    check (status in ('waiting', 'approved', 'rejected', 'resumed', 'cancelled')),
  constraint agent_checkpoints_risk_level_chk
    check (risk_level in ('low', 'medium', 'high')),
  constraint agent_checkpoints_thread_len_chk check (char_length(thread_id) between 1 and 160),
  constraint agent_checkpoints_key_len_chk check (char_length(checkpoint_key) between 1 and 160),
  constraint agent_checkpoints_interrupt_len_chk check (char_length(interrupt_before) between 1 and 160),
  constraint agent_checkpoints_action_type_len_chk check (char_length(action_type) between 1 and 80),
  constraint agent_checkpoints_payload_len_chk check (octet_length(action_payload) <= 8192),
  constraint agent_checkpoints_payload_json_chk check (jsonb_typeof(action_payload::jsonb) is not null),
  constraint agent_checkpoints_resume_len_chk check (resume_payload is null or octet_length(resume_payload) <= 4096),
  constraint agent_checkpoints_resume_json_chk check (resume_payload is null or jsonb_typeof(resume_payload::jsonb) is not null)
);

create index if not exists agent_checkpoints_owner_status_created_idx
  on public.agent_checkpoints (owner_id, status, created_at desc, id desc);
create index if not exists agent_checkpoints_proposal_waiting_idx
  on public.agent_checkpoints (proposal_id)
  where proposal_id is not null and status = 'waiting';
create index if not exists agent_checkpoints_owner_task_status_idx
  on public.agent_checkpoints (owner_id, task_id, status)
  where task_id is not null;
