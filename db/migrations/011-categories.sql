-- Capture user-managed categories.
-- Categories are owner-scoped metadata rows; tasks keep the category name for sync-friendly reads.

\connect postgres;

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

insert into public.categories (owner_id, name, color)
select candidate.owner_id, candidate.name, '#9BA1A6'
  from (
    select distinct owner_id, btrim(category) as name
      from public.tasks
     where category is not null
       and btrim(category) <> ''
    union
    select distinct owner_id, btrim(suggested_category) as name
      from public.tasks
     where suggested_category is not null
       and btrim(suggested_category) <> ''
  ) candidate
 where not exists (
       select 1
         from public.categories c
        where c.owner_id = candidate.owner_id
          and lower(c.name) = lower(candidate.name)
 );

do $$
begin
  if not exists (
    select 1
      from pg_publication_tables
     where pubname = 'powersync'
       and schemaname = 'public'
       and tablename = 'categories'
  ) then
    alter publication powersync add table public.categories;
  end if;
end $$;
