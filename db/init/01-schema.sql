-- Capture — task schema (M1).
-- Canonical task model with an explicit lifecycle. Only `confirmed`+ items are "real" todos.
-- Source of truth for PowerSync replication (synced to client SQLite, shared by the Mac Mini agent).

\connect postgres;

-- Lifecycle: proposed -> confirmed -> active -> done | cancelled
create table if not exists public.tasks (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid not null,

  title                 text not null,
  notes                 text,
  status                text not null default 'proposed',
  category              text,
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
create index if not exists tasks_due_idx on public.tasks (due_at);

-- Seed: one confirmed item so a fresh client shows the active list working.
insert into public.tasks (id, owner_id, title, status, category, source, confirmed_at)
values (
  '11111111-1111-1111-1111-111111111111',
  '00000000-0000-0000-0000-000000000001',
  'Welcome — capture is instant; suggestions arrive in the background',
  'active',
  'inbox',
  'seed',
  now()
)
on conflict (id) do nothing;

-- PowerSync logical replication publication.
create publication powersync for table public.tasks;
