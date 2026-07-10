# Migration runbook - Railway to the Mac mini

This runbook moves Capture's production stack from Railway to the selected Mac mini without
rewriting the application or creating parallel lifecycle, write-path, or enrichment logic.

The rollout is deliberately two-stage:

1. **Private first:** expose Capture only to the existing tailnet with Tailscale Serve.
2. **Public later:** switch the same `*.ts.net:10000` endpoint to Tailscale Funnel after the
   private deployment has proved stable.

The endpoint does not change between stages, so the public switch does not require another client
release.

## Current status

- [x] Production stack and single-origin edge implemented in `docker-compose.yaml`.
- [x] Native and web releases can receive deployment endpoints from GitHub Actions variables.
- [x] Railway export, target restore, manifest comparison, integrity checks, backups, and write
      freeze tooling implemented.
- [x] Existing OpenClaw Tailscale services identified and protected.
- [ ] Mac mini container runtime bootstrapped.
- [ ] Dry-run Railway snapshot restored and verified on the Mac mini.
- [ ] iOS, macOS, Share Extension, App Intents, and web verified against private Tailscale Serve.
- [ ] Final write freeze, export, restore, and production cutover completed.
- [ ] Tailscale Funnel enabled after the private soak.
- [ ] Railway retained frozen for at least seven days, then decommissioned.

## Design constraints

- The Mac mini already uses Tailscale HTTPS ports **443** and **8443** for OpenClaw. Capture must
  not reset, replace, or reconfigure those listeners.
- Tailscale Funnel supports port **10000**, which is free on the Mac mini.
- Clients should see one stable HTTPS origin:

  ```text
  https://<mini-dns>.ts.net:10000
  ```

- Postgres and the PowerSync admin API remain loopback/container-only.
- The background worker must run natively on macOS so it can invoke the local OpenClaw harness.
- Railway remains the rollback system until the Mac mini has completed a seven-day soak.

## Target architecture

```text
tailnet now / internet later
             |
             | HTTPS :10000
             v
       Tailscale Serve
       (later Funnel)
             |
             | HTTP 127.0.0.1:10000
             v
     capture-edge (Caddy)
       /api/*     -> backend:6060
       /sync/*    -> powersync:8080
       /probes/*  -> powersync:8080
       everything else -> web:3000

     Compose network
       backend -> postgres
       powersync -> postgres + backend JWKS
       web -> static files

     macOS host
       worker/src/index.ts -> loopback Postgres
       local harness -> OpenClaw on the same Mac
```

This keeps the existing Client-Server and Modular Monolith boundaries. Caddy is routing only; it
does not own authentication, writes, sync rules, or task lifecycle behaviour.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | Use one `*.ts.net:10000` origin for web, backend, and PowerSync. | Avoids consuming OpenClaw's ports and lets clients use one stable endpoint. |
| D2 | Route by existing URL namespace: `/api`, `/sync`, `/probes`, then web fallback. | Preserves upstream paths and avoids a new path-prefix contract. |
| D3 | Use Tailscale Serve first, then Funnel on the same port. | Private verification precedes public exposure; no second release is needed. |
| D4 | Use Colima plus Docker Compose on the Mac mini. | Headless, scriptable, and compatible with the existing images. |
| D5 | Run the canonical worker natively through launchd. | A Linux container cannot invoke the Mac's OpenClaw binary or local worktree safely. |
| D6 | Use a short write freeze plus custom-format dump/restore. | The database is small; the simplest recoverable migration is preferable to live logical replication. |
| D7 | Rebuild the `powersync` database from source data. | It is derived state; rebuilding avoids stale checkpoints and replication positions. |
| D8 | Keep Railway backend/worker at zero replicas for at least seven days. | Rollback is a controlled re-enable, not a reconstruction under pressure. |

## Canonical homes

The migration must not fork these behaviours:

- Task lifecycle state machine:
  `clients/CaptureCore/Sources/CaptureCore/TaskStore.swift`
- Backend write allowlist:
  `backend/src/index.ts`
- Background enrichment and local-harness execution:
  `worker/src/index.ts`
- Owner-scoped sync rules:
  `infra/powersync/sync-config.yaml`
- Stack topology:
  `docker-compose.yaml`
- Secrets loading:
  `scripts/with-secrets.sh`

## Client endpoint release

Native release builds read endpoint settings from their own bundle:

```text
CAPTURE_BACKEND_HOST=<mini-dns>.ts.net:10000
CAPTURE_POWERSYNC_HOST=<mini-dns>.ts.net:10000
```

The Share Extension has its own Info.plist and must receive the same settings. App Intents live in
the main iOS target and inherit its bundle settings.

The web build receives full URLs:

```text
VITE_BACKEND_URL=https://<mini-dns>.ts.net:10000
VITE_POWERSYNC_URL=https://<mini-dns>.ts.net:10000
```

Set these as GitHub Actions repository variables. The hostname is configuration, not a credential;
no API key or database secret is embedded in the clients.

`CaptureConfig.fromEnvironment()` ignores unresolved `$(...)` build placeholders and falls back to
the existing Railway production endpoints. That keeps local and emergency builds safe when the
repository variables are absent.

## Secrets

Production secrets live in the macOS Keychain service `capture`. Commands run through:

```bash
CAPTURE_KEYCHAIN_OVERRIDE=1 scripts/with-secrets.sh <command>
```

The override is intentional on the production Mac: Keychain values must win over ignored local
development env files.

Required production values:

- `PG_DATABASE_PASSWORD`
- `CAPTURE_API_SECRET`
- `PS_API_TOKEN`
- `BACKEND_JWT_PRIVATE_KEY`
- `RAILWAY_API_TOKEN` and `RAILWAY_PROJECT_ID` while migration/rollback remains available
- the configured mail-provider credential
- `OPENAI_API_KEY` when LLM enrichment is enabled
- local harness settings when approved execution is enabled

Never put these values in the repository, command output, issue text, or agent prompts.

## Phase 1 - Bootstrap the Mac mini

Run on the Mac mini:

```bash
cd ~/work/todo
CAPTURE_KEYCHAIN_OVERRIDE=1 scripts/with-secrets.sh scripts/mac-mini.sh bootstrap
```

This installs/starts Colima, Docker CLI, Docker Compose, jq, and Node. It does not touch the
existing Tailscale Serve/Funnel configuration.

Build and start the stack:

```bash
CAPTURE_KEYCHAIN_OVERRIDE=1 scripts/with-secrets.sh scripts/mac-mini.sh deploy
```

The production command starts only:

- `pg-db`
- `backend`
- `powersync`
- `web`
- `capture-edge`

The Docker worker remains stopped. The native launchd worker runs the same `worker/src/index.ts`
against loopback Postgres.

Verify the loopback edge:

```bash
CAPTURE_KEYCHAIN_OVERRIDE=1 scripts/with-secrets.sh scripts/mac-mini.sh health
```

## Phase 2 - Private Tailscale Serve

Add only Capture's port 10000 listener:

```bash
CAPTURE_KEYCHAIN_OVERRIDE=1 scripts/with-secrets.sh \
  scripts/mac-mini.sh tailscale-private
```

The command snapshots all non-10000 Tailscale configuration before and after the change and fails
if the existing 443/8443 OpenClaw entries differ.

Inspect only Capture's exposure:

```bash
scripts/mac-mini.sh tailscale-status
```

Private health checks:

```bash
curl https://<mini-dns>.ts.net:10000/api/health
curl https://<mini-dns>.ts.net:10000/api/auth/keys
curl https://<mini-dns>.ts.net:10000/probes/liveness
curl https://<mini-dns>.ts.net:10000/
```

## Phase 3 - Dry-run data migration

Export a read-only Railway snapshot from an authorised machine:

```bash
RAILWAY_PROJECT_ID=<project-id> \
  scripts/with-secrets.sh scripts/railway-postgres-export.sh \
  --output-dir <secure-directory>
```

The export produces:

- a PostgreSQL 18 custom-format dump
- a deterministic manifest of every public table count
- task-event high/low timestamps
- schema column and constraint fingerprints
- SHA-256 files for the dump and manifest

Copy the dump and manifest to the Mac mini over an encrypted channel, then restore:

```bash
CAPTURE_KEYCHAIN_OVERRIDE=1 scripts/with-secrets.sh scripts/mac-mini.sh restore \
  --dump <capture-railway-...dump> \
  --manifest <capture-railway-...manifest> \
  --confirm-restore
```

Restore behaviour:

1. Validate the dump catalogue.
2. Stop the edge, backend, PowerSync, web, Docker worker, and native launchd worker.
3. Take a pre-restore target backup.
4. Drop stale PowerSync replication slots.
5. Recreate the source and derived databases.
6. Restore with `--exit-on-error`, without owner/privilege drift.
7. Generate the target manifest and require an exact match.
8. Check parent/child integrity, task-event references, validated constraints, and publication
   membership.
9. Start the stack and native worker only after every gate passes.

If any comparison or integrity gate fails, dependent services remain stopped.

## Phase 4 - Release and private verification

Set the four GitHub Actions variables, then run the iOS, macOS, and web release workflows. On each
surface verify:

1. Sign-in succeeds.
2. A new capture becomes `proposed`.
3. Confirming it moves it through the canonical lifecycle.
4. A second device receives the change through PowerSync.
5. The Share Extension and App Intents submit to the same endpoint.
6. A proposed item receives worker enrichment.
7. An approved local-harness attempt is executed by the Mac worker and writes a completed or failed
   event with harness/device metadata.

Do not freeze Railway while clients are still pinned to the Railway endpoint.

## Phase 5 - Final cutover

At the agreed quiet window:

```bash
scripts/with-secrets.sh scripts/railway-write-gate.sh freeze --confirm-freeze
```

This scales Railway `backend` and `worker` to zero. PowerSync remains online for read-only rollback
visibility.

Take a final export, transfer it, and run the same guarded restore command. Then verify:

```bash
curl https://<mini-dns>.ts.net:10000/api/health
curl https://<mini-dns>.ts.net:10000/probes/liveness
```

Behavioural gate:

1. Existing tasks and task-event history are visible.
2. Capture -> propose -> confirm works.
3. The change syncs to a second device.
4. Worker enrichment completes.
5. The local harness executes one approved smoke attempt and records its outcome.

Keep Railway frozen, not deleted.

## Phase 6 - Launchd and backups

Install the user agents:

```bash
CAPTURE_KEYCHAIN_OVERRIDE=1 scripts/with-secrets.sh \
  scripts/mac-mini.sh install-launchd
```

Installed services:

- `dev.crmitchelmore.capture.stack`: starts Colima and the Compose stack, then checks it every five
  minutes.
- `dev.crmitchelmore.capture.worker`: keeps the native canonical worker running.
- `dev.crmitchelmore.capture.backup`: creates a verified source-database dump nightly at 03:15.

Backups default to:

```text
~/Library/Application Support/Capture/backups
```

Set `CAPTURE_BACKUP_DIR` to an external or replicated destination. The deployment script never
deletes older dumps; apply an operator-managed retention policy to that destination.

## Phase 7 - Public Funnel

After the private deployment has remained stable:

```bash
CAPTURE_KEYCHAIN_OVERRIDE=1 scripts/with-secrets.sh \
  scripts/mac-mini.sh tailscale-public --confirm-public
```

This changes only port 10000 from tailnet-only Serve to public Funnel. The hostname, port, client
configuration, database, and Compose routing remain unchanged.

Before enabling Funnel:

- confirm the backend brute-force controls are active
- confirm `PS_API_TOKEN` is strong
- confirm only `/api`, `/sync`, `/probes`, and web routes are reachable
- confirm Postgres is loopback-only
- confirm backups and monitoring are current

## Rollback

If private or public verification fails:

1. Stop using the Mac endpoint.
2. Re-enable Railway writes:

   ```bash
   scripts/with-secrets.sh scripts/railway-write-gate.sh \
     unfreeze --confirm-unfreeze
   ```

3. Release/revert client endpoint variables to Railway if clients cannot be redirected immediately.
4. Compare writes made after the freeze timestamp before replaying anything.
5. Preserve the Mac database and logs for diagnosis; do not overwrite Railway with unreviewed data.

## Risk register

| Risk | Guard |
|---|---|
| OpenClaw outage caused by resetting Tailscale | Port-10000 commands compare all protected 443/8443 config before/after. |
| Public database exposure | All host mappings default to `127.0.0.1`; only the Caddy edge is served by Tailscale. |
| Invalid sync tokens after restart | Persistent `BACKEND_JWT_PRIVATE_KEY` is required in production. |
| Stale PowerSync buckets/replication position | Restore drops PowerSync slots and recreates the derived database. |
| Partial restore accepted as success | `pg_restore --exit-on-error`, exact manifest comparison, and integrity SQL are mandatory. |
| Worker cannot run the Mac harness | Production worker runs natively through launchd, using `worker/src/index.ts`. |
| Container dependency mismatch | Backend/worker Docker contexts exclude host `node_modules` and use lockfile-based `npm ci`. |
| Mac reboot leaves services down | launchd restarts Colima/Compose and keeps the native worker alive. |
| Disk fills with logs/backups | Compose log rotation is bounded; backup location/retention are explicit. |
| Split-brain during rollback | Railway writes are frozen before the final export and remain frozen until rollback or decommission. |

## Conformance rationale

- **Conceptual Integrity -> Modular Monolith / Client-Server / Layered Architecture ->** routing
  and deployment change location only; lifecycle, writes, sync rules, and enrichment stay in their
  canonical modules.
- **Design for Production / Stability -> Repository / Idempotency / Guard Clause ->** destructive
  restore requires explicit confirmation, takes a backup first, rebuilds derived state, and fails
  closed on any manifest or integrity mismatch.
- **Outcome Over Output -> Materialized View / DTO ->** success is measured by restored durable
  state and cross-device behaviour, not by containers merely starting.
- **Human-Centred Design -> Arrange-Act-Assert ->** the private stage makes failure recoverable and
  the verification steps mirror real capture, confirmation, sync, and local-agent flows.
