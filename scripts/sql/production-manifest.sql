\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
\pset fieldsep '|'

select format(
  'select %L, count(*)::text from %I.%I;',
  'table:' || schemaname || '.' || tablename,
  schemaname,
  tablename
)
from pg_tables
where schemaname = 'public'
order by tablename
\gexec

select
  'task_events:min_created_at',
  coalesce(min(created_at)::text, '')
from public.task_events;

select
  'task_events:max_created_at',
  coalesce(max(created_at)::text, '')
from public.task_events;

select
  'schema:columns_md5',
  md5(string_agg(
    table_schema || '.' || table_name || ':' || ordinal_position || ':' ||
    column_name || ':' || data_type || ':' || is_nullable,
    ',' order by table_schema, table_name, ordinal_position
  ))
from information_schema.columns
where table_schema = 'public';

select
  'schema:constraints_md5',
  md5(string_agg(
    conrelid::regclass::text || ':' || conname || ':' || pg_get_constraintdef(oid),
    ',' order by conrelid::regclass::text, conname
  ))
from pg_constraint
where connamespace = 'public'::regnamespace;
