# Sign in with Apple — rollout runbook

Capture moved from a single shared API secret to per-user **Sign in with Apple**. Every client now
signs in, the backend issues an opaque, revocable session token, and PowerSync only syncs the rows
each user owns (`WHERE owner_id = auth.user_id()`).

This change is **coordinated and partly destructive**, so it is intentionally a deliberate go-live
rather than an automatic deploy:

- The migration deletes the old single-user (`DEV_USER_ID`) tasks/tags — a fresh start (approved).
- The new backend rejects the old static secret, so the **currently-installed Mac/iOS builds stop
  syncing** until they are replaced with the sign-in builds.
- Sign in with Apple can only be verified **interactively** (your Apple ID + Face ID/Touch ID).

Do the steps below in order, in one sitting.

## 0. Prerequisites (Apple Developer portal — one-time)

App IDs (team `8X4ZN58TYH`):

- `dev.crmitchelmore.capture.ios` (iOS app)
- `dev.crmitchelmore.capture.mac` (macOS app)
- `dev.crmitchelmore.capture.ios.share` (share extension — no auth needed)

1. For the **iOS** and **macOS** App IDs, enable the **Sign in with Apple** capability.
2. Group both under **one primary App ID** so Apple issues the **same `sub`** for you on both
   platforms (otherwise iOS-you and Mac-you would be two separate accounts). In the capability
   config, set one as primary and the other as "Grouped with primary App ID".
3. Regenerate the provisioning profiles that the iOS app + macOS app are signed with so they carry
   the new `com.apple.developer.applesignin` entitlement (already added to the entitlements files).
4. **Web only** (optional, deferred): create a **Services ID** `dev.crmitchelmore.capture.web`,
   enable Sign in with Apple on it, register the hosted HTTPS domain + return URL, and verify the
   domain. The web sign-in cannot work until the web app is hosted on that domain.

> The App Store Connect API key `Y6C8R5DA75` can toggle the bundle-id capability, but grouping,
> Services IDs and domain verification are portal UI steps.

## 1. Backend environment (Railway `backend` service)

Set these env vars on the backend service (project `ee351d08-1020-464d-a8af-7616085de5a4`):

| Var | Value |
| --- | --- |
| `BACKEND_JWT_PRIVATE_KEY` | The persistent RS256 private key PEM (newlines as literal `\n`). Generated locally with `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048`. Keeps the JWKS stable across restarts so in-flight PowerSync tokens stay valid. |
| `APPLE_NATIVE_AUD` | `dev.crmitchelmore.capture.ios,dev.crmitchelmore.capture.mac` (comma-separated; default already matches). |
| `APPLE_WEB_AUD` | `dev.crmitchelmore.capture.web` |
| `JWT_AUDIENCE` | `powersync` (already the default). |

Generate + set the key (run from a checkout; do **not** commit the PEM):

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /tmp/capture-jwt-private.pem
ONE_LINE=$(awk 'BEGIN{ORS="\\n"} {print}' /tmp/capture-jwt-private.pem)
railway variables --service backend \
  --project ee351d08-1020-464d-a8af-7616085de5a4 \
  --environment 585ea813-c8be-481c-9713-9f0387ca4331 \
  --set "BACKEND_JWT_PRIVATE_KEY=$ONE_LINE"
```

(`RAILWAY_API_TOKEN` = the account token; **not** `RAILWAY_TOKEN`.)

## 2. Migrate the live database

Apply `db/migrations/002-auth.sql` over the Railway TCP proxy. The **real** Postgres password lives
inside the backend's `BACKEND_DATABASE_URI` env var (the `POSTGRES_PASSWORD` var is stale).

```bash
# Pull the password from the backend service env, then:
psql "postgresql://postgres:<password>@acela.proxy.rlwy.net:45610/postgres" \
  -f db/migrations/002-auth.sql
```

The migration is additive (creates `users`, `user_identities`, `sessions`; adds `owner_id` FKs;
deletes the old `DEV_USER_ID` rows) and idempotent.

## 3. Deploy backend + PowerSync (from repo root)

```bash
railway up --ci --service backend  --project ee351d08-... --environment 585ea813-...
railway up --ci --service powersync --project ee351d08-... --environment 585ea813-...
```

PowerSync picks up the new per-user `sync-config.yaml` (baked into its image) and the tightened
`audience: ["powersync"]` on restart.

## 4. Ship the native builds

- **macOS**: build + sign + notarize, then install (or `git tag mac-v0.x.y && git push --tags` for
  the Sparkle release). See `docs/mac-release.md`.
- **iOS**: archive + upload to TestFlight. See `docs/testflight.md`.

Both now require the Sign in with Apple entitlement — make sure the regenerated provisioning
profiles (step 0.3) are used.

## 5. Verify (interactive — you)

1. Open the Mac app → you should see the **Sign in with Apple** gate. Sign in.
2. Capture a todo → confirm it → it should stay `active` and appear in Postgres with **your** new
   `users.id` as `owner_id`.
3. Open the iOS app, sign in with the **same Apple ID** → the same todos sync in (proves shared
   `sub` / per-user sync).
4. Two-user isolation check: sign in on a second Apple ID (or ask a second person) → confirm they
   see **none** of your rows and you see none of theirs.
5. Sign out on the Mac → the local list clears and the gate returns.

## Rollback

- The migration is additive; to revert behaviour, redeploy the previous backend image (pre-auth)
  and restore the old `sync-config.yaml`. The dropped `DEV_USER_ID` rows are not recoverable (this
  was an accepted fresh start).
