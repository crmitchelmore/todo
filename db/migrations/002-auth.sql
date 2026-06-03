-- Capture — multi-user auth (Sign in with Apple).
-- Additive, idempotent migration applied to the LIVE Postgres (run via psql over the proxy).
-- Adds the identity model and makes task/tag ownership a real foreign key.
--
-- Fresh-start policy (user chose NOT to migrate the single-user data): the old DEV_USER_ID
-- rows are removed so the NOT NULL FK on owner_id can be added cleanly. Anyone who signs in
-- gets their own user id; no new row is ever assigned the legacy DEV_USER_ID.

\connect postgres;

-- A person. Identity providers attach to this via user_identities so adding Google/email/passkey
-- later is purely additive (no reshaping of ownership).
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
  provider_subject  text not null,            -- Apple `sub` (stable per-user, per-team)
  email             text,
  created_at        timestamptz not null default now(),
  unique (provider, provider_subject)
);
create index if not exists user_identities_user_idx on public.user_identities (user_id);

-- Opaque, revocable sessions. The client holds a random token; we only ever store its SHA-256.
-- Revocation (logout / Apple credential revoked / account deletion) is just a row update.
create table if not exists public.sessions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.users(id) on delete cascade,
  token_hash    text not null unique,         -- sha256(opaque token), hex
  client        text,                         -- 'ios' | 'macos' | 'web' (metadata only)
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null,
  last_seen_at  timestamptz,
  revoked_at    timestamptz
);
create index if not exists sessions_user_idx on public.sessions (user_id);
create index if not exists sessions_lookup_idx on public.sessions (token_hash) where revoked_at is null;

-- Fresh start: drop legacy single-user data so the ownership FK can be enforced.
delete from public.tasks where owner_id = '00000000-0000-0000-0000-000000000001';
delete from public.tags  where owner_id = '00000000-0000-0000-0000-000000000001';

-- Ownership becomes a real foreign key (defensive: DB-level isolation, not just app code).
do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'tasks_owner_fk'
  ) then
    alter table public.tasks
      add constraint tasks_owner_fk foreign key (owner_id) references public.users(id) on delete cascade;
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'tags_owner_fk'
  ) then
    alter table public.tags
      add constraint tags_owner_fk foreign key (owner_id) references public.users(id) on delete cascade;
  end if;
end $$;

-- Compound access path for per-user sync rules and owner-scoped writes.
create index if not exists tasks_owner_id_idx on public.tasks (owner_id, id);
create index if not exists tags_owner_id_idx  on public.tags  (owner_id, id);
