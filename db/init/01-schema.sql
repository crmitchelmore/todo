-- Capture — task schema (M1).
-- Canonical task model with an explicit lifecycle. Only `confirmed`+ items are "real" todos.
-- Source of truth for PowerSync replication (synced to client SQLite, shared by the Mac Mini agent).

\connect postgres;

-- A person. Identity providers attach via user_identities so adding Google/email/passkey later
-- is purely additive (no reshaping of ownership).
create table if not exists public.users (
  id          uuid primary key default gen_random_uuid(),
  email       text,
  created_at  timestamptz not null default now()
);

-- Federated identity: (provider, subject) is globally unique and maps to exactly one user.
create table if not exists public.user_identities (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.users(id) on delete cascade,
  provider          text not null,            -- 'apple' (future: 'google', 'email', ...)
  provider_subject  text not null,            -- Apple `sub`
  email             text,
  created_at        timestamptz not null default now(),
  unique (provider, provider_subject)
);
create index if not exists user_identities_user_idx on public.user_identities (user_id);

-- Opaque, revocable sessions. The client holds a random token; we only store its SHA-256.
create table if not exists public.sessions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.users(id) on delete cascade,
  token_hash    text not null unique,
  client        text,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null,
  last_seen_at  timestamptz,
  revoked_at    timestamptz
);
create index if not exists sessions_user_idx on public.sessions (user_id);
create index if not exists sessions_lookup_idx on public.sessions (token_hash) where revoked_at is null;

-- Additive auth hardening: passkeys/WebAuthn, TOTP MFA, and one-time recovery codes.
create table if not exists public.auth_totp_secrets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users(id) on delete cascade,
  secret      text not null,
  enabled_at  timestamptz,
  disabled_at timestamptz,
  created_at  timestamptz not null default now()
);
create unique index if not exists auth_totp_one_active_idx
  on public.auth_totp_secrets (user_id)
  where enabled_at is not null and disabled_at is null;

create table if not exists public.auth_recovery_codes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users(id) on delete cascade,
  code_hash   text not null,
  used_at     timestamptz,
  revoked_at  timestamptz,
  created_at  timestamptz not null default now(),
  unique (user_id, code_hash)
);
create index if not exists auth_recovery_codes_user_active_idx
  on public.auth_recovery_codes (user_id)
  where used_at is null and revoked_at is null;

create table if not exists public.auth_mfa_challenges (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users(id) on delete cascade,
  token_hash  text not null unique,
  attempts    integer not null default 0,
  expires_at  timestamptz not null,
  consumed_at timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists auth_mfa_challenges_lookup_idx
  on public.auth_mfa_challenges (token_hash)
  where consumed_at is null;

create table if not exists public.auth_webauthn_credentials (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.users(id) on delete cascade,
  credential_id text not null unique,
  public_key    bytea not null,
  counter       bigint not null default 0,
  transports    text[] not null default '{}',
  device_type   text,
  backed_up     boolean not null default false,
  name          text,
  created_at    timestamptz not null default now(),
  last_used_at  timestamptz,
  revoked_at    timestamptz
);
create index if not exists auth_webauthn_credentials_user_active_idx
  on public.auth_webauthn_credentials (user_id)
  where revoked_at is null;

create table if not exists public.auth_webauthn_challenges (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references public.users(id) on delete cascade,
  purpose        text not null check (purpose in ('registration', 'authentication')),
  challenge_hash text not null unique,
  expires_at     timestamptz not null,
  consumed_at    timestamptz,
  created_at     timestamptz not null default now()
);
create index if not exists auth_webauthn_challenges_lookup_idx
  on public.auth_webauthn_challenges (challenge_hash, purpose)
  where consumed_at is null;

-- Lifecycle: proposed -> confirmed -> active -> done | cancelled
create table if not exists public.tasks (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid not null references public.users(id) on delete cascade,

  title                 text not null,
  notes                 text,
  status                text not null default 'proposed',
  parent_task_id        uuid,
  category              text,
  tags                  text,                          -- JSON array of tag names
  due_at                timestamptz,
  priority              integer,                       -- 0 = highest .. 4 = lowest
  github_repo           text,                          -- Optional owner/repo association for engineering work
  github_url            text,
  agent_mode            text not null default 'research',
  agent_plan_confirmation integer not null default 1,

  -- Background suggestions (filled asynchronously after instant capture; never block the write).
  suggested_due_at      timestamptz,
  suggested_category    text,
  suggestion_confidence double precision,
  suggestion_source     text,                          -- e.g. 'on-device', 'agent'

  -- Provenance (where the item came from: 'capture', 'gmail', 'agent', ...).
  source                text not null default 'capture',

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  confirmed_at          timestamptz,
  completed_at          timestamptz
);

create index if not exists tasks_owner_status_idx on public.tasks (owner_id, status);
create index if not exists tasks_owner_id_idx on public.tasks (owner_id, id);
create index if not exists tasks_due_idx on public.tasks (due_at);
create index if not exists tasks_owner_parent_idx on public.tasks (owner_id, parent_task_id, status, created_at desc);
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

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'tasks_parent_not_self_chk'
       and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_parent_not_self_chk
      check (parent_task_id is null or parent_task_id <> id);
  end if;
end $$;

do $$
begin
      if not exists (
      select 1
        from pg_constraint
       where conname = 'tasks_github_repo_len_chk'
         and conrelid = 'public.tasks'::regclass
      ) then
      alter table public.tasks
        add constraint tasks_github_repo_len_chk
        check (github_repo is null or char_length(github_repo) between 1 and 160);
      end if;
end $$;

do $$
begin
      if not exists (
      select 1
        from pg_constraint
       where conname = 'tasks_github_url_len_chk'
         and conrelid = 'public.tasks'::regclass
      ) then
      alter table public.tasks
        add constraint tasks_github_url_len_chk
        check (github_url is null or char_length(github_url) between 1 and 500);
      end if;
end $$;

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

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'tasks_parent_owner_fk'
       and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_parent_owner_fk
      foreign key (owner_id, parent_task_id)
      references public.tasks(owner_id, id);
  end if;
end $$;

create or replace function public.prevent_task_parent_cycle()
returns trigger
language plpgsql
as $$
begin
  if new.parent_task_id is null then
    return new;
  end if;

  if exists (
    with recursive ancestors(id, parent_task_id, path) as (
      select t.id, t.parent_task_id, array[t.id]
        from public.tasks t
       where t.owner_id = new.owner_id
         and t.id = new.parent_task_id
      union all
      select t.id, t.parent_task_id, a.path || t.id
        from public.tasks t
        join ancestors a on a.parent_task_id = t.id
       where t.owner_id = new.owner_id
         and not t.id = any(a.path)
    )
    select 1 from ancestors where id = new.id
  ) then
    raise exception 'task hierarchy cycle detected for task %', new.id
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists tasks_parent_no_cycle_trg on public.tasks;
create trigger tasks_parent_no_cycle_trg
  before insert or update of id, owner_id, parent_task_id on public.tasks
  for each row
  execute function public.prevent_task_parent_cycle();

-- User-managed tags. Tasks reference tags by name in their JSON `tags` column; this table holds
-- presentation metadata (colour) for management.
create table if not exists public.tags (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.users(id) on delete cascade,
  name        text not null,
  color       text not null default '#9BA1A6',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create unique index if not exists tags_owner_name_idx on public.tags (owner_id, lower(name));
create index if not exists tags_owner_id_idx on public.tags (owner_id, id);

-- User-managed categories. Tasks reference categories by name; this table holds the editable
-- category vocabulary and presentation metadata.
create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.users(id) on delete cascade,
  name        text not null,
  color       text not null default '#9BA1A6',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint categories_name_len_chk check (char_length(name) between 1 and 80),
  constraint categories_color_hex_chk check (color ~ '^#[0-9A-Fa-f]{6}$')
);

create unique index if not exists categories_owner_name_idx on public.categories (owner_id, lower(name));
create index if not exists categories_owner_id_idx on public.categories (owner_id, id);

-- User-owned guidance for background categorisation. The worker reads these as suggestion hints
-- only; task status/category/tag changes still require normal human confirmation.
create table if not exists public.categorisation_rules (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references public.users(id) on delete cascade,
  title         text not null,
  instructions  text not null,
  category      text,
  tags          text,
  enabled       integer not null default 1,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint categorisation_rules_title_len_chk check (char_length(title) between 1 and 120),
  constraint categorisation_rules_instructions_len_chk check (char_length(instructions) between 1 and 1000),
  constraint categorisation_rules_category_len_chk check (category is null or char_length(category) between 1 and 80),
  constraint categorisation_rules_tags_len_chk check (tags is null or octet_length(tags) <= 2000),
  constraint categorisation_rules_tags_json_chk check (tags is null or jsonb_typeof(tags::jsonb) = 'array'),
  constraint categorisation_rules_enabled_chk check (enabled in (0, 1))
);

create index if not exists categorisation_rules_owner_enabled_idx
  on public.categorisation_rules (owner_id, enabled, updated_at desc);

-- User-visible memory/facts that guide agent research. These are owner-scoped, editable, and
-- soft-deletable so an agent cannot permanently erase context through a retried write.
create table if not exists public.user_memories (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.users(id) on delete cascade,
  content     text not null,
  domain      text,
  source      text not null default 'manual',
  confidence  double precision not null default 1,
  tags        text,
  status      text not null default 'active',
  expires_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,

  constraint user_memories_content_len_chk check (char_length(content) between 1 and 1000),
  constraint user_memories_domain_len_chk check (domain is null or char_length(domain) between 1 and 80),
  constraint user_memories_source_chk check (source in ('manual', 'correction', 'inferred', 'agent')),
  constraint user_memories_confidence_chk check (confidence >= 0 and confidence <= 1),
  constraint user_memories_tags_len_chk check (tags is null or octet_length(tags) <= 2000),
  constraint user_memories_tags_json_chk check (tags is null or jsonb_typeof(tags::jsonb) = 'array'),
  constraint user_memories_status_chk check (status in ('active', 'disabled', 'deleted')),
  constraint user_memories_deleted_at_chk check ((status = 'deleted') = (deleted_at is not null))
);

create index if not exists user_memories_owner_status_expires_idx
  on public.user_memories (owner_id, status, expires_at, updated_at desc);

-- Owner-scoped local backend device registry. Multiple Macs can install Capture, while one active
-- device may be selected to execute approved local harness attempts.
create table if not exists public.agent_devices (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid not null references public.users(id) on delete cascade,
  device_name         text not null,
  platform            text not null default 'macos',
  status              text not null default 'active',
  is_selected_backend integer not null default 0,
  harness_kind        text,
  harness_label       text,
  capabilities        text,
  last_seen_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint agent_devices_name_len_chk check (char_length(device_name) between 1 and 120),
  constraint agent_devices_platform_len_chk check (char_length(platform) between 1 and 40),
  constraint agent_devices_status_chk check (status in ('active', 'disabled')),
  constraint agent_devices_selected_chk check (is_selected_backend in (0, 1)),
  constraint agent_devices_harness_kind_chk
    check (harness_kind is null or harness_kind in ('codex', 'copilot-cli', 'hermes', 'openclaw', 'custom')),
  constraint agent_devices_harness_label_len_chk
    check (harness_label is null or char_length(harness_label) between 1 and 120),
  constraint agent_devices_capabilities_len_chk
    check (capabilities is null or octet_length(capabilities) <= 4000),
  constraint agent_devices_capabilities_json_chk
    check (capabilities is null or jsonb_typeof(capabilities::jsonb) is not null)
);

create unique index if not exists agent_devices_one_selected_backend_idx
  on public.agent_devices (owner_id)
  where status = 'active' and is_selected_backend = 1;

create index if not exists agent_devices_owner_status_seen_idx
  on public.agent_devices (owner_id, status, last_seen_at desc, updated_at desc);

-- Server-owned, append-only task history / agent work log. Synced read-only to clients and loaded
-- only for the selected task; callers mutate tasks, the backend/worker records events.
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
      'agent_failed',
      'commented'
    )),
  constraint task_events_title_len_chk check (char_length(title) between 1 and 160),
  constraint task_events_body_len_chk check (body is null or char_length(body) <= 2000),
  constraint task_events_metadata_len_chk check (metadata is null or octet_length(metadata) <= 4096),
  constraint task_events_metadata_json_chk check (metadata is null or jsonb_typeof(metadata::jsonb) is not null)
);
create index if not exists task_events_owner_task_created_idx
  on public.task_events (owner_id, task_id, created_at desc, id desc);
create index if not exists task_events_owner_created_idx
  on public.task_events (owner_id, created_at desc, id desc);
create index if not exists task_events_agent_requests_idx
  on public.task_events (created_at asc, owner_id, task_id)
  where event_type = 'agent_requested';
create index if not exists task_events_agent_results_request_idx
  on public.task_events (owner_id, task_id, ((metadata::jsonb ->> 'request_id')))
  where event_type in ('agent_completed', 'agent_failed') and metadata is not null;

-- User-attached images. The synced row stores bounded preview data only, so task history can render
-- instantly on every device without pushing full-resolution blobs through PowerSync.
create table if not exists public.task_attachments (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null,
  task_id          uuid not null,
  filename         text,
  mime_type        text not null,
  byte_size        integer not null,
  preview_data_url text not null,
  created_at       timestamptz not null default now(),

  constraint task_attachments_owner_task_fk
    foreign key (owner_id, task_id)
    references public.tasks(owner_id, id)
    on delete cascade,
  constraint task_attachments_mime_chk
    check (mime_type in ('image/jpeg', 'image/png', 'image/webp', 'image/gif')),
  constraint task_attachments_byte_size_chk
    check (byte_size between 1 and 524288),
  constraint task_attachments_filename_len_chk
    check (filename is null or char_length(filename) between 1 and 160),
  constraint task_attachments_preview_len_chk
    check (octet_length(preview_data_url) <= 819200),
  constraint task_attachments_preview_data_url_chk
    check (left(preview_data_url, 11) = 'data:image/')
);
create index if not exists task_attachments_owner_task_created_idx
  on public.task_attachments (owner_id, task_id, created_at desc, id desc);

-- Synced notification history. Server/worker-owned rows let every client show missed
-- research/attempt/interview notifications and optionally raise local OS notifications.
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

-- Server/agent-owned proposals that are surfaced through existing confirm-card task rows.
-- Clients read this provenance/confidence stream, but do not upload rows to it.
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

-- Server/agent-owned pause points for consequential actions; not synced directly.
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

-- PowerSync logical replication publication.
create publication powersync for table public.tasks, public.tags, public.categories, public.categorisation_rules, public.user_memories, public.agent_devices, public.task_events, public.task_attachments, public.agent_proposals, public.notifications;
