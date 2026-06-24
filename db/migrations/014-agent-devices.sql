-- Owner-scoped local backend device registry.
-- Clients may install Capture on multiple Macs, but only one active device should be selected as
-- the backend computer that runs approved local harness attempts.

create table if not exists public.agent_devices (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid not null references public.users(id) on delete cascade,
  device_name         text not null,
  platform            text not null default 'macos',
  status              text not null default 'active',
  is_selected_backend integer not null default 0,
  harness_kind        text,
  harness_label       text,
  capabilities        text,
  last_seen_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint agent_devices_name_len_chk check (char_length(device_name) between 1 and 120),
  constraint agent_devices_platform_len_chk check (char_length(platform) between 1 and 40),
  constraint agent_devices_status_chk check (status in ('active', 'disabled')),
  constraint agent_devices_selected_chk check (is_selected_backend in (0, 1)),
  constraint agent_devices_harness_kind_chk
    check (harness_kind is null or harness_kind in ('copilot-cli', 'hermes', 'openclaw', 'custom')),
  constraint agent_devices_harness_label_len_chk
    check (harness_label is null or char_length(harness_label) between 1 and 120),
  constraint agent_devices_capabilities_len_chk
    check (capabilities is null or octet_length(capabilities) <= 4000),
  constraint agent_devices_capabilities_json_chk
    check (capabilities is null or jsonb_typeof(capabilities::jsonb) is not null)
);

create unique index if not exists agent_devices_one_selected_backend_idx
  on public.agent_devices (owner_id)
  where status = 'active' and is_selected_backend = 1;

create index if not exists agent_devices_owner_status_seen_idx
  on public.agent_devices (owner_id, status, last_seen_at desc, updated_at desc);

alter publication powersync add table public.agent_devices;
