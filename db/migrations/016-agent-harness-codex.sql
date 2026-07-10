-- Add Codex as the preferred local harness kind. Keep copilot-cli accepted as a legacy value so
-- existing registered devices continue to sync and can be migrated in place.

alter table public.agent_devices
  drop constraint if exists agent_devices_harness_kind_chk;

alter table public.agent_devices
  add constraint agent_devices_harness_kind_chk
  check (harness_kind is null or harness_kind in ('codex', 'copilot-cli', 'hermes', 'openclaw', 'custom'));
