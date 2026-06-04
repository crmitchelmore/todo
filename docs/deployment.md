# Deploying Capture

Capture's backend is a small, self-contained stack. The clients (iOS, macOS, web) are
local-first and only need to reach **two HTTPS services**:

| Service | Port | Role |
|---|---|---|
| **backend** | 6060 | Mints JWTs (RS256) + JWKS, applies the write path, `POST /api/capture` ingestion |
| **powersync** | 8080 | Streams bucket data to clients; replicates from Postgres |
| postgres | 5432 | Source of truth (`wal_level=logical`) **and** PowerSync bucket storage (separate `powersync` database) |
| worker | – | Background enrichment (no inbound port) |

Clients only ever talk to **backend** and **powersync**. Everything else is internal.

> **One database engine.** PowerSync uses Postgres for bucket storage (a dedicated `powersync`
> database on the same instance, separate tables), so there is no MongoDB to run.

---

## Production: Railway (current deployment)

The live stack runs on [Railway](https://railway.app) in the **`capture`** project, four services
in one private network:

| Railway service | Image / source | Public domain |
|---|---|---|
| `postgres` | `postgres:18` (custom start: `wal_level=logical`) | TCP proxy only |
| `backend` | `backend/` (node:20-slim) | `backend-production-de2f.up.railway.app` |
| `powersync` | `infra/powersync/Dockerfile` | `powersync-production-e560.up.railway.app` |
| `worker` | `worker/` (node:20-slim) | none (no inbound) |

### How services connect

Services reach each other over Railway's **private network** using each service's
`RAILWAY_PRIVATE_DOMAIN`. **Important:** use the service's *actual* private domain
(e.g. `postgres-22d88df1.railway.internal`), **not** the bare `postgres.railway.internal` —
the un-suffixed name can be reserved/misroute and will fail auth. Read the real value from the
service's `RAILWAY_PRIVATE_DOMAIN` variable.

Key environment variables:

| Service | Variable | Value (shape) |
|---|---|---|
| postgres | `POSTGRES_USER` / `POSTGRES_DB` / `POSTGRES_PASSWORD` | `postgres` / `postgres` / *(secret)* |
| backend | `BACKEND_DATABASE_URI` | `postgres://postgres:<pw>@<pg-private>:5432/postgres` |
| backend | `POWERSYNC_PUBLIC_URL` | `https://powersync-production-e560.up.railway.app` |
| backend | `MAIL_PROVIDER` | optional: `smtp`, `resend`, `brevo`, `sendgrid`, or `postmark` |
| backend | `MAIL_FROM` | sender identity, e.g. `Capture <hello@example.com>` |
| backend | `SMTP_URL` / provider key | one of `SMTP_URL`, `RESEND_API_KEY`, `BREVO_API_KEY`, `SENDGRID_API_KEY`, `POSTMARK_SERVER_TOKEN` |
| powersync | `PS_DATA_SOURCE_URI` | `postgres://postgres:<pw>@<pg-private>:5432/postgres` |
| powersync | `PS_STORAGE_URI` | `postgres://postgres:<pw>@<pg-private>:5432/powersync` |
| powersync | `PS_JWKS_URL` | `http://backend.railway.internal:6060/api/auth/keys` |
| powersync | `PS_PORT` | `8080` |
| worker | `WORKER_DATABASE_URI` | `postgres://postgres:<pw>@<pg-private>:5432/postgres` |

> **Postgres without TLS on the private network.** `sslmode` is **not** read from the connection
> URI by PowerSync — it must be set explicitly. `infra/powersync/service.yaml` sets
> `sslmode: disable` on **both** the replication connection and the storage block. Leaving it off
> makes PowerSync default to `verify-full`, which fails against the non-TLS private Postgres.

> **First-init password.** `POSTGRES_PASSWORD` only sets the role password on the *first* volume
> init. If you change it later, the running cluster keeps the old password and internal
> (scram) auth fails even though the proxy (loopback `trust`) still works. Fix with
> `ALTER USER postgres WITH PASSWORD '<pw>';` over the TCP proxy.

### Deploying code

Source builds use the Railway CLI authenticated with a Railway token. In this repo, prefer
`RAILWAY_API_TOKEN` for non-interactive agent/shell deploys:

```bash
export RAILWAY_API_TOKEN=<token>
cd /path/to/todo

# backend and powersync have Railway root-directory config, so upload from repo root.
railway up --ci --service backend
railway up --ci --service powersync

# worker currently has no Railway root-directory config; make worker/ the archive root.
railway up ./worker --path-as-root --ci --service worker
```

> **Upload-root gotcha.** Do not use `--path-as-root` for services that already have a Railway
> root directory configured (`backend`, `powersync`): Railway will look for `/backend` inside the
> uploaded archive and fail. Conversely, uploading the repo root for `worker` makes Railpack inspect
> the monorepo root and fail to infer the Node app; use `./worker --path-as-root` until the service
> gets a root directory configured in Railway settings.

`infra/powersync/Dockerfile` bakes `service.yaml` + `sync-config.yaml` into the image (so no
volume mount is needed) and points `POWERSYNC_CONFIG_PATH` at `/config/service.yaml`.

### Verifying

```bash
curl https://backend-production-de2f.up.railway.app/api/auth/keys          # 200 JWKS
curl https://powersync-production-e560.up.railway.app/probes/liveness       # {"ready":true,...}
# End-to-end capture:
curl -X POST https://backend-production-de2f.up.railway.app/api/capture \
  -H 'Content-Type: application/json' -d '{"raw_text":"buy milk tomorrow 5pm"}'
```

---

## Pointing clients at the deployment

**Native (iOS/macOS):** the apps resolve config via `CaptureConfig.fromEnvironment()`, which
defaults to `CaptureConfig.production` (the Railway domains above). To target a local stack in
dev, set both `CAPTURE_BACKEND_HOST` and `CAPTURE_POWERSYNC_HOST` (e.g. to `localhost:6060` /
`localhost:8080`) in the Xcode scheme or Info.plist.

**Web:** set the two Vite vars (see `web/.env.example`):

```
VITE_BACKEND_URL=https://backend-production-de2f.up.railway.app
VITE_POWERSYNC_URL=https://powersync-production-e560.up.railway.app
```

---

## Local development (docker-compose)

For local iteration the whole stack runs from `docker-compose.yaml` (Postgres source + Postgres
bucket storage + backend + powersync + worker):

```bash
cp .env.example .env        # fill in secrets
docker compose up --build
```

Then run the clients against `localhost` by setting the env/Vite vars to the `localhost:6060`
(backend) and `localhost:8080` (powersync) pair.

---

## Alternatives

- **PowerSync Cloud** — instead of self-hosting the `powersync` service, point PowerSync Cloud at
  the Railway Postgres source. Removes the `powersync` service + bucket-storage database from your
  ops surface; adds a vendor/cost. The client model is unchanged.
- **Any container host** — the same four images (Postgres, `backend/`, `infra/powersync`,
  `worker/`) run on Fly.io, Render, a single VM with docker-compose, etc. Only the private host
  names and public domains differ.

---

## Client distribution

The backend deploy (above) covers the servers. The three clients ship on their own tracks:

### iOS app + Share Extension + App Intents
- **TestFlight (recommended)** — archive `CaptureiOS` in Xcode (or `xcodebuild archive`), upload to
  App Store Connect, distribute to yourself/testers. Requires an Apple Developer Program membership
  ($99/yr) and the `group.dev.crmitchelmore.capture` App Group + the two bundle IDs
  (`dev.crmitchelmore.capture.ios`, `…ios.share`) registered. App Intents (Siri/Shortcuts/Action
  Button) and the Share Extension ship inside the same archive.
- **Ad-hoc / development** — install directly to a registered device over USB/Wi-Fi from Xcode for
  personal use without TestFlight.

Release automation should prefer official, auditable tools first: `release-ios.yml`, `xcodebuild`,
`xcrun altool` / App Store Connect API credentials, and `gh workflow run release-ios.yml --ref main`.
Use browser automation only for the Apple Developer portal gaps that the API key cannot mutate, such
as assigning App Groups to App IDs. For that class of workflow, use Webwright/Playwright against a
user-signed-in browser session, keep screenshots/logs as artefacts, and never store Apple passwords
or 2FA codes in the repo.

### macOS app
- **Developer ID + notarization (recommended for personal use off the App Store)** — archive
  `CaptureMac`, export with a Developer ID Application cert, `notarytool submit … --wait`, then
  `stapler staple`. Ship the `.app` in a DMG/zip. The global ⌥Space hotkey + menubar item work
  outside the sandbox.
- **Mac App Store** — alternative if you want managed updates; requires sandboxing review.
- **Unsigned local build** — `xcodebuild … CODE_SIGNING_ALLOWED=NO` for running on your own machine
  during development (what the repo's build commands use).

### Web app
- **Static host** — `cd web && npm run build` produces a static bundle; deploy `web/dist` to any
  static host (Vercel, Netlify, Cloudflare Pages, or a Railway static service). Set
  `VITE_BACKEND_URL` / `VITE_POWERSYNC_URL` at build time to the Railway domains.
- **Same-project on Railway** — add a static/Nginx service to the `capture` project so everything
  lives in one place.

> Whichever track: the clients only need the two public HTTPS domains. No client embeds secrets —
> the backend mints short-lived JWTs and the capture endpoint is the only write path.
