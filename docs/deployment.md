# Deploying Capture

Capture's backend is a small, self-contained stack. The clients (iOS, macOS, web) are
local-first and only need to reach **two HTTP services**:

| Service | Port | Role |
|---|---|---|
| **backend** | 6060 | Mints JWTs (RS256) + JWKS, applies the write path, `POST /api/capture` ingestion |
| **powersync** | 8080 | Streams bucket data to clients; replicates from Postgres |
| postgres | 5432 | Source of truth (`wal_level=logical`) |
| mongo | 27017 | PowerSync bucket storage (replica set) |
| worker | – | Background enrichment (no inbound port) |

Clients only ever talk to **backend** and **powersync**. Everything else is internal.

> PowerSync can also use **Postgres** for bucket storage instead of Mongo (same DB, separate
> tables) — see [Dropping Mongo](#optional-drop-mongo-postgres-bucket-storage). The default
> compose uses Mongo because that is the proven path from the PowerSync self-host demo.

---

## Recommended: Mac Mini + Tailscale (free, always-on)

Your Mac Mini already runs OpenClaw and is always on. Hosting the stack there and exposing it
over your **tailnet** means your iPhone and laptop reach it securely from anywhere with **zero
public exposure** and **valid HTTPS certs** (via Tailscale MagicDNS) — which iOS App Transport
Security requires.

### 1. Prerequisites on the Mini

```bash
# Container runtime — OrbStack (recommended on macOS) or Docker Desktop.
brew install orbstack          # then launch it once; enable "Start at login"

# Tailscale (if not already installed)
brew install --cask tailscale
```

Enable **MagicDNS** and **HTTPS Certificates** for your tailnet in the Tailscale admin console
(DNS tab → "Enable HTTPS"). Then on the Mini:

```bash
tailscale up
tailscale status        # note the Mini's name, e.g. mini.tailXXXX.ts.net
```

### 2. Clone + configure secrets

```bash
git clone https://github.com/crmitchelmore/todo.git
cd todo
cp .env.example .env
```

Edit `.env` and **change every password/secret** from the demo defaults:

```ini
PG_DATABASE_PASSWORD=<long-random>
PS_DATA_SOURCE_URI=postgres://postgres:<long-random>@pg-db:5432/postgres
BACKEND_DATABASE_URI=postgres://postgres:<long-random>@pg-db:5432/postgres
JWT_ISSUER=capture
JWT_AUDIENCE=powersync
# Optional: upgrade enrichment from deterministic to LLM
# OPENAI_API_KEY=sk-...
```

`.env` is gitignored — secrets never leave the Mini.

> Also harden `infra/powersync/service.yaml` before any non-tailnet exposure: replace the
> `api.tokens` placeholder and set `sslmode: require` if Postgres is not on a trusted network.
> Inside a single compose network on the tailnet, the defaults are fine.

### 3. Bring the stack up

```bash
docker compose up -d
docker compose ps          # all healthy
curl -fsS localhost:6060/api/auth/keys | head -c 80   # backend JWKS
curl -fsS localhost:8080/probes/liveness               # powersync
```

### 4. Expose it on the tailnet (single HTTPS origin)

```bash
./infra/selfhost/tailscale-serve.sh
```

This path-routes one HTTPS origin to both services:

```
https://mini.tailXXXX.ts.net/api/...  -> backend  (:6060)
https://mini.tailXXXX.ts.net/...      -> powersync (:8080)
```

Verify from another tailnet device (your laptop):

```bash
curl -fsS https://mini.tailXXXX.ts.net/api/auth/keys | head -c 80
curl -fsS https://mini.tailXXXX.ts.net/probes/liveness
```

### 5. Point the clients at it

**Native (iOS + macOS)** — one origin:

```swift
let config = CaptureConfig.selfHosted(host: "mini.tailXXXX.ts.net")
```

Or leave the code alone and set `CAPTURE_HOST=mini.tailXXXX.ts.net` in the scheme's environment
(`CaptureConfig.fromEnvironment()`), which falls back to `localDev` when unset.

**Web**:

```ini
VITE_BACKEND_URL=https://mini.tailXXXX.ts.net
VITE_POWERSYNC_URL=https://mini.tailXXXX.ts.net
```

### 6. Auto-start on boot

```bash
cp infra/selfhost/dev.crmitchelmore.capture.plist ~/Library/LaunchAgents/
# edit WorkingDirectory to your checkout path first
launchctl load -w ~/Library/LaunchAgents/dev.crmitchelmore.capture.plist
```

`tailscale serve` config persists across reboots once set, so the origin survives restarts.

---

## Optional: drop Mongo (Postgres bucket storage)

To run one database instead of two, point PowerSync's storage at Postgres. Edit
`infra/powersync/service.yaml`:

```yaml
storage:
  type: postgresql
  uri: !env PS_DATA_SOURCE_URI   # same Postgres; PowerSync namespaces its own tables
```

Then remove the `mongo`, `mongo-rs-init` services (and the `PS_MONGO_URI` env). This is simpler
to operate and ideal for managed-Postgres hosts (Railway/Neon/Fly), at the cost of diverging from
the demo's proven Mongo path. Validate replication after switching.

---

## Alternatives

### Railway (managed, paid)
A clean PaaS path. Provision **managed Postgres**, then deploy `backend/` and `worker/` from
their Dockerfiles and the PowerSync service from a thin image over
`journeyapps/powersync-service`. Use **Postgres bucket storage** (above) to avoid running Mongo.
Wire services over Railway private networking (`*.railway.internal`); expose only **backend** and
**powersync** with public domains.
*Note: requires an active Railway plan — a free trial will block service creation.*

### VPS (Hetzner / DigitalOcean / Fly.io)
`docker compose up -d` on any small VM works identically. Put **Caddy** in front for automatic
Let's Encrypt TLS on a real domain, path-routing `/api`→backend and `/`→powersync (same split as
the Tailscale Serve script). Lock Postgres/Mongo to the internal network.

### Managed Postgres (Neon / Supabase / RDS)
Use a managed Postgres with logical replication enabled as the source, and run only
backend + powersync + worker as containers. Reduces stateful ops you own.

---

## Distributing the clients

| Client | Options |
|---|---|
| **macOS** | (a) **Developer ID + notarization** → signed `.dmg` you install directly (best for personal use); (b) Mac App Store. The app icon is wired (`Capture.icns`). |
| **iOS** | (a) **TestFlight** (up to 100 testers, 90-day builds) — best for testing on your own devices; (b) App Store. Requires an Apple Developer Program membership ($99/yr) and the App Group `group.dev.crmitchelmore.capture` registered for the Share Extension + App Intents. |
| **web** | Static build (`cd web && npm run build`) hosted on **Vercel**, **Cloudflare Pages**, or served by the Mini itself behind Tailscale. Set `VITE_*` to the tailnet origin at build time. |

For personal use the fastest path is: **macOS** notarized DMG, **iOS** via TestFlight (or a
direct development build to your own device), **web** served from the Mini over Tailscale.
