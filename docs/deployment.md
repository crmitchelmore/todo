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
| backend/worker | `SENTRY_DSN` / `SENTRY_ENVIRONMENT` / `SENTRY_TRACES_SAMPLE_RATE` | optional Sentry errors/traces/log correlation; services still emit JSON wide events locally when unset |
| web | `VITE_SENTRY_DSN` / `VITE_SENTRY_ENVIRONMENT` | optional browser Sentry errors/traces/replay |
| iOS/Mac | `SENTRY_DSN` / `SENTRY_ENVIRONMENT` | optional native Sentry errors/traces baked into release builds; local OSLog wide events still emit when unset |
| powersync | `PS_DATA_SOURCE_URI` | `postgres://postgres:<pw>@<pg-private>:5432/postgres` |
| powersync | `PS_STORAGE_URI` | `postgres://postgres:<pw>@<pg-private>:5432/powersync` |
| powersync | `PS_JWKS_URL` | `http://backend.railway.internal:6060/api/auth/keys` |
| powersync | `PS_PORT` | `8080` |
| worker | `WORKER_DATABASE_URI` | `postgres://postgres:<pw>@<pg-private>:5432/postgres` |
| worker | `RESEARCH_LLM_MODEL` | model for automatic/manual research briefs; default `gpt-5.6-sol` |
| worker | `RESEARCH_LLM_PROVIDER` | `api` for OpenAI API key usage, or `codex` for a host worker using logged-in Codex subscription auth |
| worker | `OPENAI_API_KEY` | required when `RESEARCH_LLM_PROVIDER=api`; also enables optional LLM enrichment |
| worker | `CODEX_RESEARCH_COMMAND` / `CODEX_RESEARCH_WORKDIR` | Codex CLI command and repo workdir when `RESEARCH_LLM_PROVIDER=codex` |
| worker (local/Mac) | `CAPTURE_WORK_ROOT` | optional Git repo root to scan for engineering-task GitHub associations; macOS falls back to `~/work` |
| worker (local/Mac) | `LOCAL_HARNESS_ENABLED` | set to `1` only on the local computer assigned to execute approved agent attempts |
| worker (local/Mac) | `LOCAL_HARNESS_KIND` | `codex`, `hermes`, `openclaw`, or `custom`; legacy `copilot-cli` rows remain readable |
| worker (local/Mac) | `LOCAL_HARNESS_COMMAND` / `LOCAL_HARNESS_WORKDIR` | local harness binary and working directory on that computer |
| worker (local/Mac) | `LOCAL_HARNESS_ARGS_JSON` | optional JSON `{ "args": [...] }` template; `{prompt}` and `{timeout}` are substituted as argv values, not shell-interpolated |
| worker (local/Mac) | `LOCAL_HARNESS_AGENT` / `LOCAL_HARNESS_THINKING` | optional OpenClaw-style adapter settings when `LOCAL_HARNESS_KIND=openclaw` |
| worker (local/Mac) | `LOCAL_HARNESS_DEVICE_ID` / `LOCAL_HARNESS_DEVICE_NAME` | stable label recorded in task events so multiple Macs are distinguishable |

For this machine, prefer the Codex harness so approved local attempts use the logged-in OpenAI
subscription instead of a Copilot CLI token:

```bash
LOCAL_HARNESS_ENABLED=1
LOCAL_HARNESS_KIND=codex
LOCAL_HARNESS_COMMAND=codex
LOCAL_HARNESS_WORKDIR=/Users/bravostation/work/todo
```

For automatic research on newly added items from this Mac without an API key, run the worker on the
host with Codex subscription auth:

```bash
RESEARCH_LLM_PROVIDER=codex
RESEARCH_LLM_MODEL=gpt-5.6-sol
CODEX_RESEARCH_COMMAND=codex
CODEX_RESEARCH_WORKDIR=/Users/bravostation/work/todo
```

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
cd /path/to/todo
scripts/with-secrets.sh railway up --ci --service backend
scripts/with-secrets.sh railway up --ci --service powersync
scripts/with-secrets.sh railway up ./worker --path-as-root --ci --service worker
```

Use `scripts/with-secrets.sh` rather than calling `railway` directly. Railway CLI 5.x gives
`RAILWAY_TOKEN` precedence over `RAILWAY_API_TOKEN`; a stale legacy `RAILWAY_TOKEN` will make the
CLI report "Unauthorized" even when `RAILWAY_API_TOKEN` is valid. The wrapper normalises this by
unsetting `RAILWAY_TOKEN` whenever `RAILWAY_API_TOKEN` is available.

To open production Postgres from local terminal:

```bash
scripts/with-secrets.sh railway connect postgres
```

The `postgres` service is a custom container, not Railway's managed database plugin, so the raw
Railway CLI looks for `DATABASE_PUBLIC_URL` and fails. The wrapper handles this repo-specific case
by reading the Postgres service's TCP proxy variables and executing `psql` with `PGSSLMODE=disable`.

For local/dev commands that need credentials, keep secrets in ignored `.env.local` files or in the
macOS Keychain service `capture` using the env var as the account name:

```bash
security add-generic-password -U -s capture -a RAILWAY_API_TOKEN -w "$RAILWAY_API_TOKEN"
scripts/with-secrets.sh railway status
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
Merging changes under `clients/apps/CaptureiOS/`, `CaptureShare/`, `CaptureWidget/`, `clients/CaptureCore/`,
or `clients/apps/project.yml` to `main` automatically runs `release-ios.yml` and uploads a TestFlight
build. If the automatic run fails, fix the workflow or signing issue rather than treating the merge as
shipped.
Apple Developer accounts have hard certificate limits. Prefer reusing existing valid Apple Development,
Apple Distribution, Mac Development, and Developer ID certificates/profiles before creating new ones.
Only create a new certificate when no compatible non-expired certificate is available for the team and
target. If the account hits the certificate cap, revoke only clearly unused or expired certificates,
then rerun the release workflow; never commit certificates, profiles, passwords, or app-specific
passwords into the repository.
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

Merging changes under `clients/apps/CaptureMac/`, `clients/CaptureCore/`, or `clients/apps/project.yml`
to `main` automatically runs `release-mac.yml`, publishes a signed/notarised GitHub Release, and updates
the Sparkle appcast used by installed Mac apps.
Reuse existing Developer ID and Mac Development signing assets where possible. Do not let CI or local
automation create fresh Apple certificates on every run; certificate churn blocks both Mac and iOS
releases for the whole account.

### Web app
- **Static host** — `cd web && npm run build` produces a static bundle; deploy `web/dist` to any
  static host (Vercel, Netlify, Cloudflare Pages, or a Railway static service). Set
  `VITE_BACKEND_URL` / `VITE_POWERSYNC_URL` at build time to the Railway domains.
- **Same-project on Railway** — add a static/Nginx service to the `capture` project so everything
  lives in one place.

Merging changes under `web/` to `main` automatically runs `release-web.yml`, validates the Vite build,
and deploys the Railway `web` service. The workflow requires `RAILWAY_API_TOKEN` (or `RAILWAY_TOKEN`)
and `RAILWAY_PROJECT_ID` repository secrets so it deploys into the existing `capture` project without
interactive Railway linking.

> Whichever track: the clients only need the two public HTTPS domains. No client embeds secrets —
> the backend mints short-lived JWTs and the capture endpoint is the only write path.
