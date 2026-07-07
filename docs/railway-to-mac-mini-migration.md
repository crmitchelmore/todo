# Migration runbook — Railway → self-hosted Mac mini

Execution-ready plan to move the Capture production stack (**web, backend, powersync, worker,
postgres**) off Railway and onto a single self-hosted **Mac mini** running the existing
`docker-compose.yaml`, without rebuilding any service.

> **Guiding principle.** This is a *host move*, not a rewrite. The four server images
> (`postgres:18`, `backend/`, `infra/powersync`, `worker/`) and the web static bundle already
> run locally via `docker-compose.yaml`. We change **where** they run and **how clients reach
> them** — not the canonical homes: task lifecycle
> (`clients/CaptureCore/Sources/CaptureCore/TaskStore.swift`), write allowlist
> (`backend/src/index.ts` → `ALLOWED_COLUMNS`), enrichment (`worker/src/index.ts`). No parallel
> implementations are introduced.

See also: [`deployment.md`](deployment.md) (current Railway runbook + env-var table),
[`architecture.md`](architecture.md).

---

## 0. Assumptions & non-goals

### Assumptions
- Single-tenant / low-user production (solo + a few testers). One Mac mini is sufficient; no HA.
- Docker Desktop (or Colima/OrbStack) runs on the mini; the same `docker compose` CLI used in dev.
- Postgres holds **two logical databases on one instance**: `postgres` (source of truth,
  `wal_level=logical`) and `powersync` (PowerSync bucket storage). Confirmed by `.env.example`
  (`PS_STORAGE_URI=…/powersync`) and [`deployment.md`](deployment.md).
- Clients only ever reach **two HTTPS endpoints**: `backend` (6060, JWKS + write path + capture)
  and `powersync` (8080, sync stream + liveness). `postgres` and `worker` stay private.
- Native iOS/macOS apps hardcode the Railway domains in `CaptureConfig.production`; the web client
  reads `VITE_BACKEND_URL` / `VITE_POWERSYNC_URL` at build time. **This is the crux of cutover**
  (see §1 decision D1).
- Secrets live in the macOS Keychain (service `capture`) / ignored `.env.local`, loaded via
  `scripts/with-secrets.sh`. No secret is committed.

### Non-goals
- Not migrating to Kubernetes, Fly, Render, or PowerSync Cloud (those remain documented
  alternatives in `deployment.md`).
- Not changing the data model, sync rules, auth scheme, or the write allowlist.
- Not building new deploy tooling — we reuse `docker-compose.yaml`, `with-secrets.sh`, and
  `refresh-mac-app.sh`.
- Not shipping a client release *as part of* cutover, **except** the one-time custom-domain
  release (D1) which must land and be adopted *before* the infra move.

---

## 1. Key decisions (make these first)

| ID | Decision | Recommendation | Why it matters |
|----|----------|----------------|----------------|
| **D1** | How do native apps reach the new host? | **Move clients to stable custom domains** (e.g. `api.capture.<domain>` / `sync.capture.<domain>`) via a client release *before* migrating, then cutover is a DNS repoint. | Railway `*.up.railway.app` domains cannot be repointed to the mini. If clients keep the Railway hostnames, cutover forces an App Store/TestFlight release with its review lag. Custom domains decouple client releases from host moves permanently. |
| **D2** | Ingress / routing for a residential ISP? | Pick per §2 decision tree. Default: **Cloudflare Tunnel** (survives CGNAT, TLS + WAF, no port-forward). | Vodafone UK residential is very likely CGNAT; no inbound port-forward will work. |
| **D3** | Data migration downtime posture? | **Conservative dump/restore** for first move (simplest, verifiable). Keep the low-downtime logical-replication path (§3) as fallback if the maintenance window is unacceptable. | Solo/low-traffic ⇒ a short window is cheap; simplicity beats cleverness. |
| **D4** | Bucket-storage (`powersync` db) — migrate or rebuild? | **Rebuild from source** on first cutover (drop/recreate, let PowerSync re-replicate). Migrate it only if full client re-sync is unacceptable. | Bucket storage is derived state; PowerSync reconstructs it from the `postgres` source. Fewer moving parts. |
| **D5** | Keep Railway as hot rollback? | **Yes — keep Railway running, read-write-frozen, for ≥7 days** post-cutover. | Instant rollback = repoint DNS back. |
| **D6** | TLS termination point? | At the tunnel/edge (Cloudflare or Tailscale Funnel issue certs). Compose services stay plain-HTTP on the LAN/loopback. | PowerSync ↔ backend JWKS is already plain HTTP internally (`allow_local_jwks: true`); don't add TLS inside the compose network. |

> **D1 is the single most important pre-req.** Do it in week 1 (see §10) so the actual cutover is
> a DNS change, not a client release.

---

## 2. Routing architecture decision

Clients need **two publicly reachable HTTPS endpoints** from a residential connection. Vodafone UK
residential typically hands out **CGNAT** addresses (no inbound), and static IPv4 is generally not
offered on consumer plans.

### 2.1 Detect CGNAT / public-IP status

```bash
# What the world sees as your egress IP:
PUBLIC_IP=$(curl -s https://api.ipify.org); echo "public: $PUBLIC_IP"

# What your router's WAN interface has (check the router admin UI, or UPnP):
#   192.168.* / 10.* / 172.16-31.*  -> behind your own NAT (normal)
# The CGNAT tell: router WAN IP is in 100.64.0.0/10 (RFC 6598) OR
#   router WAN IP != $PUBLIC_IP (double NAT by the ISP).
# Reverse-path probe: does anything answer inbound on your public IP?
nc -vz "$PUBLIC_IP" 443 2>&1 | head   # times out under CGNAT / no forward

# Traceroute: multiple private/100.64 hops before the first public hop => CGNAT.
traceroute -n "$PUBLIC_IP" 2>/dev/null | head
```

**Rule of thumb:** if router-WAN-IP ≠ `api.ipify.org` result, or the WAN IP is in `100.64.0.0/10`,
you are behind CGNAT and **port-forwarding will not work** — use an outbound tunnel.

### 2.2 Options & selection criteria

| Option | Works under CGNAT? | Inbound ports needed | TLS | Cost | Best when |
|--------|:--:|--------------------|-----|------|-----------|
| **Cloudflare Tunnel** (`cloudflared`) | ✅ yes (outbound only) | none | CF-managed cert at edge | free tier fine | **Default.** CGNAT, want a stable public hostname + WAF/rate-limiting, no static IP. |
| **Tailscale Funnel** | ✅ yes | none | TS-managed (Let's Encrypt) | free tier fine | You already use Tailscale; want minimal surface; OK with `*.ts.net` hostname (⇒ set client domain to it in D1). |
| **Public IP + DDNS + caddy/nginx** | ❌ no (needs real inbound) | 443 (forwarded) | Let's Encrypt on the mini | ISP static-IP fee | Only if Vodafone provisions a static/routable IPv4 (business add-on) and you want zero third-party edge. |
| **Tailscale private-only (no Funnel)** | ✅ yes | none | TS mesh | free | If *all* clients (incl. iOS) can join the tailnet — but Share Extensions / cold Siri intents may not have the VPN up ⇒ risky for capture reliability. Not recommended as the sole path. |

### 2.3 Decision tree

```
Is the WAN IP public & routable (not 100.64/10, inbound 443 answerable)?
├─ YES ──> Does Vodafone give you a *stable* IPv4 (static or long-lease + DDNS)?
│          ├─ YES ──> Option: Public IP + DDNS + Caddy (Let's Encrypt).  [full control, no 3rd party]
│          └─ NO  ──> Cloudflare Tunnel.  [dynamic IP is irrelevant to a tunnel]
└─ NO (CGNAT) ──> Do you already run Tailscale on all client surfaces incl. iOS extensions?
           ├─ YES & OK with *.ts.net hostname ──> Tailscale Funnel.
           └─ otherwise ─────────────────────────> Cloudflare Tunnel.   (recommended default)
```

### 2.4 Security implications & tradeoffs

- **Cloudflare Tunnel:** no open inbound ports; edge TLS; free WAF + rate-limiting + Access
  (optional zero-trust in front of `backend`/`powersync`). Tradeoff: Cloudflare sees plaintext
  after TLS termination; your public hostname lives under a CF-managed zone. Lock down the origin so
  it only accepts the tunnel (bind compose ports to `127.0.0.1`, `cloudflared` connects locally).
- **Tailscale Funnel:** similar zero-inbound posture, Let's Encrypt certs, hostname is `*.ts.net`
  (feeds D1). Funnel exposes only the specific port you publish. Tradeoff: throughput/features are
  thinner than Cloudflare; fewer edge protections.
- **Public IP + Caddy:** no third party in the data path; you own certs. Tradeoff: you now run an
  internet-facing listener on a home network — needs firewall discipline, fail2ban/rate-limits, and
  a stable IP. Highest operational burden.
- **All paths:** keep `postgres` (5432) and the PowerSync **admin** API (`PS_API_TOKEN`) *off* the
  public edge. Only expose `backend:6060` and `powersync:8080` public routes. Set a strong
  `PS_API_TOKEN` (§4) regardless — never the `.env.example` placeholder.

---

## 3. Data migration strategy

Two databases move: **`postgres`** (source of truth — the real data) and **`powersync`** (bucket
storage — derived, rebuildable). Critical tables (owner-scoped, from `db/init` + `db/migrations`):
`users`, `user_identities`, `sessions`, `tasks`, `tags`, `categories`, `categorisation_rules`,
`user_memories`, `agent_devices`, `agent_proposals`, `agent_checkpoints`, `task_events`
(**append-only history — must not lose or reorder rows**), `task_attachments`, `notifications`,
plus auth tables (`auth_*`).

### 3.1 Conservative path (recommended first move) — short maintenance window

1. Announce a short window. **Freeze writes** at the edge (point the Railway public routes to a
   maintenance response, or scale `backend` to reject writes) so `postgres` is quiescent.
2. `pg_dump` the `postgres` database from Railway (custom format).
3. Bring up the mini stack empty; **restore** into its `postgres` db.
4. **Rebuild** bucket storage (D4): let PowerSync re-replicate from the restored source (drop the
   `powersync` db content or start fresh) — clients do a one-time full re-sync.
5. Run integrity checks (§3.3). Cutover DNS (§5). Unfreeze.

Downtime ≈ dump + restore + verify (minutes for a small DB).

### 3.2 Low-downtime path (fallback if the window is unacceptable)

Use Postgres **logical replication** (`postgres` already runs `wal_level=logical`):

1. Restore a base dump of `postgres` onto the mini (as §3.1 steps 2–3) **without** freezing.
2. Create a `PUBLICATION FOR ALL TABLES` on Railway and a `SUBSCRIPTION` on the mini to stream the
   delta until lag ≈ 0.
3. When lag is near zero: brief freeze, let the subscription drain, verify counts match, drop the
   subscription, then cutover DNS.
4. Rebuild PowerSync bucket storage from the now-authoritative mini source.

Downtime ≈ the final drain + verify (seconds–low minutes). More moving parts — only take this on if
§3.1's window is genuinely too long.

### 3.3 Backup/restore sequencing & verification criteria

- **Sequence:** dump `postgres` **before** touching bucket storage. Never restore bucket storage on
  top of a mismatched source — rebuild it instead.
- **Verification gate (must all pass before cutover completes):**

| Check | Command sketch | Pass criteria |
|-------|----------------|---------------|
| Row counts per critical table match | `SELECT count(*) FROM tasks;` on both sides | Equal for every critical table |
| `task_events` history intact | `SELECT count(*), max(created_at) FROM task_events;` | Equal count **and** equal max timestamp |
| No orphaned children | tasks with `parent_task_id` not in `tasks`; child rows with unknown `owner_id`/`task_id` | 0 rows |
| Owner scoping preserved | `SELECT owner_id, count(*) FROM tasks GROUP BY 1;` | Identical distribution both sides |
| Sequences/PKs restored | `pg_dump` restore log clean; spot-check a known id | No dup-key errors; known ids resolve |
| PowerSync re-replicated | `curl …/probes/liveness` + a client sync | `ready:true`; a client sees its rows |

> Prefer **behavioural verification** over trusting the dump: after restore, run an end-to-end
> capture (§6) and confirm it lands and syncs, and that an existing item still edits/confirms.

---

## 4. Phased migration runbook

Pre-reqs for the whole runbook: mini provisioned (macOS updated, Docker running, disk headroom ≥ 3×
DB size), repo cloned, Keychain populated (`RAILWAY_API_TOKEN`, `PS_API_TOKEN`, mail provider key,
`OPENAI_API_KEY` if used), chosen routing tool installed (`cloudflared` or `tailscale`).

### Phase A — Prepare clients for a portable endpoint (D1) *(do first, needs a client release)*
1. Provision custom domains and decide final hostnames (`api.…` / `sync.…`, or the `*.ts.net` pair
   if Funnel).
2. Ship a client release that points at the **custom domains** while they still resolve to Railway
   (update `CaptureConfig.production` + web `VITE_*`). Verify all surfaces adopt it.
3. **Gate:** ≥95% of active clients on the new build (or your solo devices confirmed) before Phase E.

### Phase B — Stand up the mini stack (no traffic yet)
1. Copy env: `cp .env.example .env`; put real secrets in `.env.local` / Keychain. Set a strong
   `PS_API_TOKEN` (not the placeholder). Keep compose ports bound to `127.0.0.1`.
2. `docker compose up -d --build` (§7). Confirm `pg-db`, `backend`, `powersync`, `worker` healthy.
3. Smoke the empty stack: backend JWKS 200, powersync liveness `ready:true` (§7 health checks).

### Phase C — Migrate data (§3)
1. Dump Railway `postgres`; restore into the mini `postgres`. Rebuild bucket storage (D4).
2. Run the §3.3 verification gate. Do **not** proceed until all pass.

### Phase D — Wire ingress (D2/§2)
1. Configure the tunnel: map public `api` host → `127.0.0.1:6060`, public `sync` host →
   `127.0.0.1:8080`. Keep `postgres`/admin API unmapped.
2. From an external network (LTE/phone), hit the public URLs and confirm JWKS, liveness, and a POST
   capture (§7). Confirm `PS_JWKS_URL` inside compose still resolves `backend` internally.

### Phase E — Cutover (§5)
1. Repoint the custom domains' DNS from Railway → the tunnel edge.
2. Freeze Railway writes; final delta drain if using §3.2; flip DNS; verify (§6).

### Phase F — Post-cutover operations
1. Watch worker enrichment, sync lag, and error logs for the first hour, then daily for a week.
2. Set up: nightly `pg_dump` backups off-box (e.g. to an external disk / object store), Docker
   `restart: unless-stopped` already set, log rotation, and a `launchd`/watchdog to `compose up -d`
   on reboot. Enable Sentry DSNs if desired (env in `deployment.md`).
3. Keep Railway frozen for ≥7 days (D5). Then decommission (scale to zero, export a final dump,
   archive project). Update `deployment.md` to name the mini as production.

---

## 5. Cutover choreography (minute-by-minute)

Assumes Phases A–D complete and green. `T` = cutover start.

| Time | Action | Verify / Gate |
|------|--------|---------------|
| T-24h | Announce window; confirm off-box backup of Railway `postgres` exists | Backup file restorable in a scratch DB |
| T-30m | Lower DNS TTL on custom domains to 60s (do this ≥ old-TTL earlier ideally) | `dig` shows short TTL |
| T-10m | Final mini smoke: JWKS, liveness, external capture via tunnel | All 200 / `ready:true` |
| T-2m | **Freeze Railway writes** (maintenance mode / reject writes) | New writes rejected; reads OK |
| T-0 | (§3.2 only) drain logical replication to lag≈0; verify row counts equal | Counts match; `task_events` max ts equal |
| T+1m | **Repoint DNS** `api`/`sync` → tunnel edge | `dig api.…` resolves to CF/TS |
| T+3m | Confirm clients resolve new edge (flush local DNS if needed) | External `curl` hits mini |
| T+5m | End-to-end capture from a real client; confirm sync round-trip (§6) | Row lands `active`, syncs to a 2nd client |
| T+8m | Confirm worker enrichment flips a proposed row's `suggestion_source` to `server` | Worker logs + DB show patch |
| T+10m | Unfreeze; declare cutover done | Writes accepted on mini |
| T+15m | Rollback checkpoint — go/no-go review | If any gate red → §5.1 |

### 5.1 Rollback (fast)
Repoint DNS `api`/`sync` back to Railway, unfreeze Railway writes. Because Railway stayed live
(D5) and clients use custom domains (D1), rollback is a DNS change only. Then reconcile any writes
that landed on the mini during the window (small window ⇒ manual reconcile or replay from
`task_events`).

---

## 6. Post-cutover behavioural verification (end-to-end)

Reuse the repo's review steps (README §Review steps) against the **public** endpoints:

1. Web/native capture `email Kate the report tomorrow 2pm` → instant `proposed` row with suggested
   `Tomorrow 14:00` / `work`; confirm → row `active`.
2. `docker compose exec -T pg-db psql -U postgres -d postgres -c "select title,status,due_at,category from tasks order by created_at desc limit 3;"`
   shows it.
3. Background enrichment: capture `dentist appointment next tuesday`; within seconds
   `suggestion_source` flips to `server` (worker logs).
4. Native data path: `cd clients/CaptureCore && GIT_CONFIG_COUNT=0 swift run CaptureProbe` prints a
   `PROBE_ID`; confirm the row landed and synced to a second client.
5. Multi-user scoping intact: a client only sees its own rows (sync rules unchanged).

---

## 7. Runbook commands

> Run through the secrets wrapper where creds are needed: `scripts/with-secrets.sh <cmd>`.
> Placeholders in `<…>`.

### docker compose lifecycle
```bash
cd /path/to/todo
cp .env.example .env                       # then fill .env.local / Keychain; set a strong PS_API_TOKEN
docker compose up -d --build               # start all four services
docker compose ps                          # pg-db, backend, powersync, worker => healthy/up
docker compose logs -f worker              # tail enrichment
docker compose logs -f powersync backend   # tail sync + backend
docker compose restart powersync           # required after sync-config.yaml changes
docker compose down                        # stop (keeps named volume pg_data)
docker compose down -v                     # DANGER: also drops pg_data volume (data loss)
```

### health checks
```bash
# Local (loopback) — verify before exposing:
curl -s localhost:6060/api/health                       # {"ok":true}
curl -s localhost:6060/api/auth/keys | head -c 200      # JWKS (RS256 public key set)
curl -s localhost:8080/probes/liveness                  # {"ready":true,...}

# Public (through the tunnel) — from an EXTERNAL network:
curl -s https://api.capture.<domain>/api/auth/keys | head -c 200
curl -s https://sync.capture.<domain>/probes/liveness

# End-to-end capture (auth required — POST /api/capture is behind requireAuth):
#   1) obtain a session/token via the app or /api/auth/* flow, then:
curl -s -X POST https://api.capture.<domain>/api/capture \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer <SESSION_OR_JWT>" \
  -d '{"raw_text":"buy milk tomorrow 5pm"}'
```

### pg_dump / pg_restore (example; placeholders)
```bash
# --- 1. Dump the Railway source (custom format, all of `postgres`) ---
#   Open Railway Postgres via the repo wrapper (handles the custom container + PGSSLMODE):
scripts/with-secrets.sh railway connect postgres        # interactive psql, to sanity-check first
#   For a non-interactive dump, read the TCP proxy vars and dump directly:
PGSSLMODE=disable PGPASSWORD='<RAILWAY_PG_PW>' \
  pg_dump -Fc -h <railway_tcp_proxy_host> -p <railway_tcp_proxy_port> \
  -U postgres -d postgres -f capture_source.dump

# --- 2. Restore into the mini's postgres (compose service pg-db) ---
#   Copy the dump into the container (or mount it), then restore:
docker compose cp capture_source.dump pg-db:/tmp/capture_source.dump
docker compose exec -T pg-db \
  pg_restore --clean --if-exists --no-owner --no-privileges \
  -U postgres -d postgres /tmp/capture_source.dump

# --- 3. Rebuild PowerSync bucket storage (D4): fresh `powersync` db, let PS re-replicate ---
docker compose exec -T pg-db psql -U postgres -d postgres \
  -c "SELECT 'noop';"                                   # source untouched
docker compose restart powersync                        # PS re-syncs buckets from source

# --- 4. Verify (run on BOTH old and new, compare) ---
docker compose exec -T pg-db psql -U postgres -d postgres -c \
  "SELECT 'tasks' t, count(*) FROM tasks
   UNION ALL SELECT 'task_events', count(*) FROM task_events
   UNION ALL SELECT 'users', count(*) FROM users
   UNION ALL SELECT 'agent_proposals', count(*) FROM agent_proposals;"
docker compose exec -T pg-db psql -U postgres -d postgres -c \
  "SELECT count(*) orphans FROM tasks c
   WHERE c.parent_task_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM tasks p WHERE p.id = c.parent_task_id);"
docker compose exec -T pg-db psql -U postgres -d postgres -c \
  "SELECT max(created_at) FROM task_events;"            # must equal the source's max
```

### low-downtime logical replication (§3.2, optional)
```sql
-- On Railway source:
CREATE PUBLICATION capture_pub FOR ALL TABLES;
-- On the mini (after base restore):
CREATE SUBSCRIPTION capture_sub
  CONNECTION 'host=<railway_tcp_proxy_host> port=<port> user=postgres password=<pw> dbname=postgres sslmode=disable'
  PUBLICATION capture_pub;
-- Watch lag until ~0, then at cutover:
DROP SUBSCRIPTION capture_sub;
```

---

## 8. Risk register

| # | Risk | Detection signal | Mitigation | Rollback trigger |
|---|------|------------------|------------|------------------|
| R1 | CGNAT blocks all inbound; public URLs unreachable | External `curl` to public host times out | Use Cloudflare Tunnel / Funnel (outbound only) — never rely on port-forward | Public health checks red at T-10m ⇒ abort cutover |
| R2 | Clients pinned to Railway domains ⇒ can't cut over without an app release | Native app still calls `*.up.railway.app` | Do D1/Phase A first; gate on adoption | <95% adoption ⇒ delay Phase E |
| R3 | `task_events` history lost/reordered in migration | Row count or `max(created_at)` differs between source and target | Custom-format dump + §3.3 gate; append-only, no truncation on restore | Any history mismatch ⇒ rollback, redo dump |
| R4 | Orphaned tasks / broken parent-child rollups | §3.3 orphan query returns >0 | Restore whole DB atomically (`pg_restore --clean` in one pass), verify FKs | Orphans found ⇒ rollback |
| R5 | PowerSync `sslmode`/JWKS misconfig ⇒ clients can't sync | `/probes/liveness` not ready, or clients 401 | Keep `sslmode: disable` on both PS blocks; `PS_JWKS_URL` resolves `backend` internally; `allow_local_jwks: true` | Sync broken post-flip ⇒ rollback DNS |
| R6 | Weak/placeholder `PS_API_TOKEN` exposed | Admin API reachable with default token | Set strong token; keep admin API off the public edge | Exposure discovered ⇒ rotate + re-gate |
| R7 | Mini power/reboot ⇒ stack down, no auto-restart | Uptime/health monitor alerts | `restart: unless-stopped` (set) + `launchd` watchdog to `compose up -d` on boot; UPS optional | Sustained outage ⇒ rollback to Railway |
| R8 | Home ISP outage / dynamic IP change | Public health checks fail; DDNS stale | Tunnel is IP-agnostic (mitigates); monitor + alert | Prolonged outage ⇒ rollback to Railway |
| R9 | Writes land on mini during a failed cutover, then rollback ⇒ split-brain | Divergent rows between hosts | Freeze writes during window; small window; replay from `task_events` if needed | Divergence detected ⇒ reconcile before re-attempt |
| R10 | Worker enrichment silently stops (e.g. missing `OPENAI_API_KEY`) | `suggestion_source` never flips to `server`; worker logs idle | Worker degrades to deterministic suggestions by design; verify §6 step 3; alert on stale proposals | N/A (non-blocking; fix in place) |

---

## 9. Effort estimate by phase

| Phase | Scope | Rough effort |
|-------|-------|--------------|
| A | Custom domains + client release + adoption | 0.5–1 day work + release/review lead time (TestFlight can add days) |
| B | Stand up mini stack | 0.5 day |
| C | Data migration + verification | 0.5 day (small DB); +0.5 day if using §3.2 |
| D | Ingress/tunnel wiring | 0.5 day |
| E | Cutover | ~30 min window + 1 day supervision |
| F | Post-cutover ops (backups, watchdog, monitoring) | 0.5–1 day |
| **Total** | | **~3–4 focused days** spread over ~1–2 weeks (dominated by client-release adoption in A) |

---

## 10. Realistic first-week plan

| Day | Focus | Outcome / gate |
|-----|-------|----------------|
| **1** | Provision mini (Docker, disk, repo, Keychain secrets). Run §2.1 CGNAT detection. Bring up compose empty; local health checks green (Phase B). | Stack runs locally on mini; routing option chosen (D2). |
| **2** | Phase A kickoff: register custom domains, cut a client build pointing at them (still ⇒ Railway), submit to TestFlight / deploy web. Wire the tunnel to the mini (Phase D) and test external health from LTE. | Client release in review; public health checks green via tunnel. |
| **3** | Dry-run data migration into the mini (Phase C) using a **throwaway copy** of the Railway dump; run the full §3.3 gate; run §6 end-to-end against the mini via a dev client. | Verified restore + sync round-trip on the mini; timings measured. |
| **4** | Fix anything the dry-run surfaced. Set up Phase F ops (nightly off-box `pg_dump`, `launchd` watchdog, log rotation, optional Sentry). Confirm client-release adoption climbing. | Ops hardened; adoption gate (R2) tracked. |
| **5** | If adoption gate met: schedule and execute cutover (§5) in a low-traffic window; else hold and keep monitoring adoption. Keep Railway frozen-hot for rollback (D5). | Production on mini **or** a firm cutover date with all gates green. |

---

## Appendix — canonical homes (do not fork)
- Task lifecycle state machine: `clients/CaptureCore/Sources/CaptureCore/TaskStore.swift`
- Backend write allowlist: `backend/src/index.ts` (`ALLOWED_COLUMNS`) — the only write path.
- Background enrichment: `worker/src/index.ts` (polls Postgres; **never** mutates `status`).
- Sync rules: `infra/powersync/sync-config.yaml` (owner-scoped per-stream queries).
- Stack definition: `docker-compose.yaml` (reuse as-is on the mini).
- Secrets loader: `scripts/with-secrets.sh`. Local Mac app refresh: `scripts/refresh-mac-app.sh`.
