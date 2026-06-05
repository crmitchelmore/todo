\connect postgres;

-- Optional engineering-work association discovered from a local Mac worker or accepted proposals.
-- Kept on the task row so every synced client can render and query the repo link directly.
alter table public.tasks
  add column if not exists github_repo text,
  add column if not exists github_url text;

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

alter table public.task_events
  drop constraint if exists task_events_type_chk;

alter table public.task_events
  add constraint task_events_type_chk
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
  ));
