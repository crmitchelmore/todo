\set ON_ERROR_STOP on

do $$
declare
  invalid_count bigint;
  missing_tables text;
begin
  select count(*)
    into invalid_count
    from public.tasks child
   where child.parent_task_id is not null
     and not exists (
       select 1
         from public.tasks parent
        where parent.owner_id = child.owner_id
          and parent.id = child.parent_task_id
     );
  if invalid_count <> 0 then
    raise exception 'orphaned child tasks: %', invalid_count;
  end if;

  select count(*)
    into invalid_count
    from public.task_events event
   where not exists (
     select 1
       from public.tasks task
      where task.owner_id = event.owner_id
        and task.id = event.task_id
   );
  if invalid_count <> 0 then
    raise exception 'dangling task events: %', invalid_count;
  end if;

  select count(*)
    into invalid_count
    from pg_constraint
   where connamespace = 'public'::regnamespace
     and not convalidated;
  if invalid_count <> 0 then
    raise exception 'unvalidated public constraints: %', invalid_count;
  end if;

  with expected(table_name) as (
    values
      ('tasks'),
      ('tags'),
      ('categories'),
      ('categorisation_rules'),
      ('user_memories'),
      ('agent_devices'),
      ('task_events'),
      ('task_attachments'),
      ('agent_proposals'),
      ('notifications')
  )
  select string_agg(expected.table_name, ', ' order by expected.table_name)
    into missing_tables
    from expected
   where not exists (
     select 1
       from pg_publication_tables published
      where published.pubname = 'powersync'
        and published.schemaname = 'public'
        and published.tablename = expected.table_name
   );
  if missing_tables is not null then
    raise exception 'tables missing from powersync publication: %', missing_tables;
  end if;
end $$;
