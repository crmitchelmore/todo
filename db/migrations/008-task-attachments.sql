-- Capture task image attachments.
-- Synced metadata + small preview data URLs only; full external blob storage can be added later.

\connect postgres;

create table if not exists public.task_attachments (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null,
  task_id          uuid not null,
  filename         text,
  mime_type        text not null,
  byte_size        integer not null,
  preview_data_url text not null,
  created_at       timestamptz not null default now(),

  constraint task_attachments_owner_task_fk
    foreign key (owner_id, task_id)
    references public.tasks(owner_id, id)
    on delete cascade,
  constraint task_attachments_mime_chk
    check (mime_type in ('image/jpeg', 'image/png', 'image/webp', 'image/gif')),
  constraint task_attachments_byte_size_chk
    check (byte_size between 1 and 524288),
  constraint task_attachments_filename_len_chk
    check (filename is null or char_length(filename) between 1 and 160),
  constraint task_attachments_preview_len_chk
    check (octet_length(preview_data_url) <= 819200),
  constraint task_attachments_preview_data_url_chk
    check (left(preview_data_url, 11) = 'data:image/')
);

create index if not exists task_attachments_owner_task_created_idx
  on public.task_attachments (owner_id, task_id, created_at desc, id desc);

do $$
begin
  if not exists (
    select 1
      from pg_publication_tables
     where pubname = 'powersync'
       and schemaname = 'public'
       and tablename = 'task_attachments'
  ) then
    alter publication powersync add table public.task_attachments;
  end if;
end $$;
