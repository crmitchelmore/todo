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

## Production: Mac mini over Tailscale

The live origin is:

```text
https://bravos-mac-mini.taile313a5.ts.net:10000
```

Caddy exposes one client-facing origin and preserves the existing service boundaries:

| Path | Destination |
|---|---|
| `/api/*` | backend |
| `/sync/*`, `/probes/*` | PowerSync |
| everything else | web |

Postgres, backend, PowerSync, web, and Caddy run in the production Compose profile. The canonical
worker runs natively through launchd so approved work can invoke OpenClaw on the same Mac. Host
ports remain bound to `127.0.0.1`; Tailscale exposes only the Caddy edge on port 10000.

### Deploying code

Deploy from the canonical checkout on the Mac mini:

```bash
cd /path/to/todo
git pull --rebase
scripts/with-secrets.sh scripts/mac-mini.sh deploy
scripts/with-secrets.sh scripts/mac-mini.sh health
```

Run `scripts/mac-mini.sh install-launchd` after changing the checkout path or launchd templates.
The command installs the stack watchdog, native worker, and nightly backup agents.

`.github/workflows/release-web.yml` validates the production web bundle on `main`; it deliberately
does not deploy from a GitHub-hosted runner into the private Mac. Production deployment remains an
operator action until an authenticated private runner or equivalent deployment channel is adopted.

### Secrets

The deployed Mac reads production values from ignored `.env.local`, mode `600`, through
`scripts/with-secrets.sh`. macOS Keychain entries remain supported as optional overrides, but the
login Keychain is not the canonical source on this headless deployment.

Required production values include:

- `PG_DATABASE_PASSWORD`
- `CAPTURE_API_SECRET`
- `PS_API_TOKEN`
- `BACKEND_JWT_PRIVATE_KEY`
- the configured mail-provider credential
- local-harness values when approved execution is enabled

Never put credentials in tracked env files, client bundles, issue text, or command output.

### Exposure

Private tailnet access:

```bash
scripts/with-secrets.sh scripts/mac-mini.sh tailscale-private
```

Public Funnel access:

```bash
scripts/with-secrets.sh scripts/mac-mini.sh tailscale-public --confirm-public
```

Both commands modify only port 10000 and verify that OpenClaw's existing Tailscale listeners on
ports 443 and 8443 remain unchanged.

### Verifying

```bash
ORIGIN=https://bravos-mac-mini.taile313a5.ts.net:10000
curl --fail "$ORIGIN/"
curl --fail "$ORIGIN/api/health"
curl --fail "$ORIGIN/api/auth/keys"
curl --fail "$ORIGIN/probes/liveness"
```

For behavioural verification, run the acceptance suite with the same origin for
`CAPTURE_WEB_URL`, `CAPTURE_BACKEND_URL`, and `CAPTURE_POWERSYNC_URL`.

### Backups and restore

Nightly backups contain a custom-format dump, deterministic source manifest, and SHA-256 files:

```bash
scripts/with-secrets.sh scripts/mac-mini.sh backup
```

Restore is guarded, takes another pre-restore backup, rebuilds derived PowerSync storage, compares
the manifest exactly, and runs integrity SQL before restarting services:

```bash
scripts/with-secrets.sh scripts/mac-mini.sh restore \
  --dump /path/to/capture-postgres-<timestamp>.dump \
  --manifest /path/to/capture-postgres-<timestamp>.manifest \
  --confirm-restore
```

### Pointing clients at production

Native release builds receive host values without a scheme:

```text
CAPTURE_BACKEND_HOST=bravos-mac-mini.taile313a5.ts.net:10000
CAPTURE_POWERSYNC_HOST=bravos-mac-mini.taile313a5.ts.net:10000
```

The web build receives full URLs:

```text
VITE_BACKEND_URL=https://bravos-mac-mini.taile313a5.ts.net:10000
VITE_POWERSYNC_URL=https://bravos-mac-mini.taile313a5.ts.net:10000
```

These values are GitHub Actions repository variables, not secrets. Swift and web production
fallbacks use the same origin so missing release injection cannot silently target Railway.

Web passkeys can use the HTTPS origin. Native passkeys require a later public custom domain on
port 443 because Apple Associated Domains validation does not support this port-10000 endpoint.
Email/password and email-code authentication remain supported on every client.

---

## Local development

For local iteration, run the Compose development stack and point clients at localhost:

```bash
cp .env.example .env
docker compose up --build
```

Use `localhost:6060` for the backend and `localhost:8080` for PowerSync. The production profile,
launchd worker, Tailscale exposure, and production `.env.local` are not required for development.

---

## Railway migration archive

Railway application deployments were removed after the final verified database cutover. Migration,
snapshot, integrity, and historical rollback procedures remain in
[`railway-to-mac-mini-migration.md`](railway-to-mac-mini-migration.md); they are not the current
deployment path.

---

## Client distribution

The Mac deployment above covers the servers. The three clients ship on their own tracks:

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
- `scripts/mac-mini.sh deploy` rebuilds the web image with the production endpoint variables and
  restarts the Caddy-backed service.
- Merging changes under `web/` to `main` runs `release-web.yml` to typecheck, test, and build the
  production bundle. It does not contact Railway or mutate production.

> Clients need only the single HTTPS origin. No client embeds database credentials — the backend
> mints short-lived JWTs and the capture endpoint is the only write path.
