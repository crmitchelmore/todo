-- Capture task hierarchy.
-- Projects are ordinary tasks with recursively assigned subtasks.

\connect postgres;

alter table public.tasks
  add column if not exists parent_task_id uuid;

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

create index if not exists tasks_owner_parent_idx
  on public.tasks (owner_id, parent_task_id, status, created_at desc);
