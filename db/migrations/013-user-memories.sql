-- Capture user-visible memories for agent context.
-- Agents read active, non-expired rows as context only; users can disable/delete facts.

\connect postgres;

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

do $$
begin
  if not exists (
    select 1
      from pg_publication_tables
     where pubname = 'powersync'
       and schemaname = 'public'
       and tablename = 'user_memories'
  ) then
    alter publication powersync add table public.user_memories;
  end if;
end $$;
