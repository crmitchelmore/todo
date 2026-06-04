-- Capture — additive passkeys/WebAuthn + TOTP MFA auth material.
-- Defensive shape: owner-scoped rows, active-partial indexes, one-time challenges, and no hard
-- deletes for authenticators/recovery codes during normal disable/rotation flows.

\connect postgres;

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
