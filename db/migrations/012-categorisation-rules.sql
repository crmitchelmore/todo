-- Capture user-managed AI categorisation rules.
-- Rules are suggestions only: the worker reads them to populate suggestion_* fields and proposal
-- context, but task confirmation remains human-gated.

\connect postgres;

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

do $$
begin
  if not exists (
    select 1
      from pg_publication_tables
     where pubname = 'powersync'
       and schemaname = 'public'
       and tablename = 'categorisation_rules'
  ) then
    alter publication powersync add table public.categorisation_rules;
  end if;
end $$;
