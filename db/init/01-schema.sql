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

-- Lifecycle: proposed -> confirmed -> active -> done | cancelled
create table if not exists public.tasks (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid not null references public.users(id) on delete cascade,

  title                 text not null,
  notes                 text,
  status                text not null default 'proposed',
  category              text,
  tags                  text,                          -- JSON array of tag names ("projects" are tags)
  due_at                timestamptz,
  priority              integer,                       -- 0 = highest .. 4 = lowest

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

-- User-managed tags (a "project" is just a tag). Tasks reference tags by name in their JSON
-- `tags` column; this table holds presentation metadata (colour) for management.
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

-- PowerSync logical replication publication.
create publication powersync for table public.tasks, public.tags;
