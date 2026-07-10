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
- [x] Mac mini container runtime bootstrapped.
- [x] Dry-run Railway snapshot restored and verified on the Mac mini.
- [x] iOS, macOS, Share Extension, App Intents, and web verified against private Tailscale Serve.
- [x] Final write freeze, export, restore, and production cutover completed.
- [x] Railway application deployments removed after the replacement passed its gates.
- [x] Tailscale Funnel enabled on port 10000 without changing OpenClaw's protected listeners.
- [ ] Public flow verified from outside the tailnet (`cap-3c1.3`).
- [ ] PR #25 merged and production promoted to the canonical `main` checkout (`cap-3c1.2`).
- [ ] Backups replicated and restore-rehearsed off-device (`cap-3c1.4`).
- [ ] Secure Mac mini production deployment automated (`cap-3c1.5`).
- [ ] Railway Hobby subscription cancellation confirmed in the authenticated billing dashboard
      (`cap-3c1.1`).

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
- The final Railway dump, manifest, checksums, and retained volume are migration archives; Railway
  is no longer the active production or rollback runtime.

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
| D8 | Remove Railway deployments after the Mac replacement passes data and behaviour gates. | Stops compute spend while retaining the verified export and volume until billing cancellation. |

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
the same Mac mini production origin. This prevents a missing release variable from silently
targeting a decommissioned environment.

Native passkeys are the exception to the port-10000 strategy. Apple's Associated Domains service
validates `webcredentials` on public HTTPS port 443, so the private Serve stage must use email/code
or password sign-in. A public Funnel on port 10000 makes Capture internet-reachable but does not
restore native passkeys; that requires a later stable custom domain on port 443 (for example through
an outbound tunnel) and a matching entitlement release.

## Secrets

Production secrets live in ignored `.env.local`, mode `600`, on the Mac mini. Commands run through:

```bash
scripts/with-secrets.sh <command>
```

The macOS Keychain service `capture` remains an optional source where non-GUI Keychain access is
reliable; it is not the canonical source on this headless deployment.

Required production values:

- `PG_DATABASE_PASSWORD`
- `CAPTURE_API_SECRET`
- `PS_API_TOKEN`
- `BACKEND_JWT_PRIVATE_KEY`
- `RAILWAY_API_TOKEN` and `RAILWAY_PROJECT_ID` only for historical migration or billing inspection
- the configured mail-provider credential
- `OPENAI_API_KEY` when LLM enrichment is enabled
- local harness settings when approved execution is enabled

Never put these values in the repository, command output, issue text, or agent prompts.

## Phase 1 - Bootstrap the Mac mini

Run on the Mac mini:

```bash
cd ~/work/todo
scripts/with-secrets.sh scripts/mac-mini.sh bootstrap
```

This installs/starts Colima, Docker CLI, Docker Compose, jq, and Node. It does not touch the
existing Tailscale Serve/Funnel configuration.

Build and start the stack:

```bash
scripts/with-secrets.sh scripts/mac-mini.sh deploy
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
scripts/with-secrets.sh scripts/mac-mini.sh health
```

## Phase 2 - Private Tailscale Serve

Add only Capture's port 10000 listener:

```bash
scripts/with-secrets.sh scripts/mac-mini.sh tailscale-private
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
scripts/with-secrets.sh scripts/mac-mini.sh restore \
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

Set the four GitHub Actions variables, run the iOS and macOS release workflows, validate the web
bundle with `release-web.yml`, and deploy the Mac stack. On each surface verify:

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

This removes the Railway `backend` and `worker` deployments. PowerSync remains online for
read-only rollback visibility.

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

After the replacement passes its final gates, remove every Railway deployment while retaining the
Postgres volume until billing cancellation:

```bash
scripts/with-secrets.sh scripts/railway-write-gate.sh \
  pause-all --confirm-pause-all
```

## Phase 6 - Launchd and backups

Install the user agents:

```bash
scripts/with-secrets.sh scripts/mac-mini.sh install-launchd
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

Each run writes a custom-format dump, deterministic manifest, and SHA-256 files, so the guarded
restore command can consume the backup directly. Set `CAPTURE_BACKUP_DIR` to an external or
replicated destination. The deployment script never deletes older backups; apply an
operator-managed retention policy to that destination.

## Phase 7 - Interim public Funnel

After the private deployment has remained stable:

```bash
scripts/with-secrets.sh scripts/mac-mini.sh tailscale-public --confirm-public
```

This changes only port 10000 from tailnet-only Serve to public Funnel. The hostname, port, client
configuration, database, and Compose routing remain unchanged.

This is sufficient for public web/API/sync access. Native passkeys remain disabled until Capture
has a dedicated public port-443 domain and the Apple associated-domain entitlement is updated.

Before enabling Funnel:

- confirm the backend brute-force controls are active
- confirm `PS_API_TOKEN` is strong
- confirm only `/api`, `/sync`, `/probes`, and web routes are reachable
- confirm Postgres is loopback-only
- confirm backups and monitoring are current

## Rollback

If public verification fails:

1. Switch port 10000 back to tailnet-only Serve:

   ```bash
   scripts/with-secrets.sh scripts/mac-mini.sh tailscale-private
   ```

2. Keep clients on the same origin; only its reachability changes.
3. If application code is faulty, deploy the last known-good commit on the Mac.
4. If durable state is faulty, restore a verified local dump and matching manifest with
   `scripts/mac-mini.sh restore --confirm-restore`.
5. Preserve the failed database and logs for diagnosis before restoring or replaying writes.

Railway is no longer an active rollback target. Reactivating its archived project would be a
separate recovery decision requiring a write comparison against the Mac source of truth.

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
| Split-brain during rollback | Only the Mac accepts writes; recovery restores a verified local backup rather than starting a second writer. |
| Native passkeys fail on the port-10000 endpoint | Use email/code or password during the Tailscale stage; add a dedicated public port-443 domain before re-enabling passkeys. |

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
