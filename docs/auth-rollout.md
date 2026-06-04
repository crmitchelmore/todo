# Auth rollout runbook — multi-user auth

Capture uses per-user **email + password** auth with additive passwordless email-code, web
passkeys, and TOTP 2FA foundations. Each client
signs in or registers, the backend issues an **opaque, revocable session token**, and PowerSync
only syncs the rows each user owns (`WHERE owner_id = auth.user_id()`).

> History: we briefly shipped Sign in with Apple but reverted it — a grouped/secondary Mac App ID
> can't carry the `applesignin` entitlement in its Developer ID provisioning profile, so the Mac
> build was unsignable. Email + password removes all Apple-portal dependency and is deterministic
> across surfaces (same email+password ⇒ same backend user ⇒ todos sync).

## Design (what's deployed)

Two credentials, by design:

1. **Opaque session token** — random; only its SHA-256 is stored in `public.sessions`. Sent as a
   Bearer token to the REST backend. Revocable (logout / account deletion = a row update).
2. **Short-lived RS256 PowerSync JWT** — `aud=powersync`, `sub=users.id`, ~5 min TTL. Minted
   per-request via `GET /api/auth/token`, verified by PowerSync against the backend JWKS
   (`GET /api/auth/keys`).

Per-user isolation is enforced at the **database boundary**: `owner_id` foreign keys on
`tasks`/`tags` (cascade on user delete) plus the PowerSync per-user sync filter. `owner_id` is
forced server-side from the session — never trusted from the client.

Passwords: **bcryptjs** (pure-JS, cost 12) with a SHA-256 base64 pre-hash to bound input under
bcrypt's 72-byte truncation limit. Stored self-describing as `bcrypt-sha256$<hash>` so a future
argon2id migration is a clean swap. Email is normalised (lower+trim) **server-side** before
insert; a partial unique index on `lower(email)` is the uniqueness + login-lookup path.

Passkeys/TOTP are additive auth material: WebAuthn credentials and challenges are owner-scoped;
TOTP secrets can be disabled without deleting rows; recovery codes are stored only as hashes and
returned exactly once on creation/rotation. Every first-factor session issuance path must go
through MFA-aware session issuance. Passkey login is treated as MFA-equivalent only because
registration and login both require WebAuthn user verification.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/auth/register` | Create account → `{session_token, user_id}` (409 if email taken) |
| POST | `/api/auth/login` | `{session_token, user_id}`; generic 401 for unknown email **or** wrong password |
| POST | `/api/auth/login/mfa` | Complete a password login when `/login` returns `mfa_required` |
| POST | `/api/auth/logout` | Revoke the current session |
| POST | `/api/auth/email-code` | Email a one-time sign-in code; always 200 if the email shape is valid |
| POST | `/api/auth/email-code/verify` | Verify the sign-in code and return `{session_token, user_id}` |
| POST | `/api/auth/forgot` | Email a password-reset code; always 200 if the email shape is valid |
| POST | `/api/auth/reset` | Verify reset code, set a new password, revoke old sessions, return a fresh session |
| POST | `/api/auth/totp/setup` | Start TOTP setup for the signed-in user; returns secret/otpauth URI |
| POST | `/api/auth/totp/verify` | Verify setup code; enables TOTP and returns one-time recovery codes |
| POST | `/api/auth/totp/disable` | Disable TOTP after TOTP/recovery verification |
| POST | `/api/auth/recovery-codes/rotate` | Rotate recovery codes after TOTP/recovery verification |
| POST | `/api/auth/passkeys/register/options` | WebAuthn registration options for the signed-in user |
| POST | `/api/auth/passkeys/register/verify` | Verify and store a passkey credential |
| POST | `/api/auth/passkeys/login/options` | WebAuthn authentication options |
| POST | `/api/auth/passkeys/login/verify` | Verify passkey assertion and return a session |
| GET | `/api/auth/token` | Mint a short-lived per-user PowerSync JWT |
| GET | `/api/auth/keys` | JWKS for PowerSync to verify the sync JWT |

A pre-bcrypt in-memory throttle (10 failed logins / 15 min per ip+email) runs **before** the
hash compare. `trust proxy` is on so the client IP is the real one behind Railway.

Passkeys require the backend to know the exact browser origin and relying-party ID. For production,
set `PUBLIC_WEB_ORIGIN=https://<web-host>` and `WEBAUTHN_RP_ID=<web-hostname>` on the backend
before enabling the web UI broadly.

## Go-live (DONE on 2026-06-03)

1. **Migration** — `db/migrations/002-auth.sql` applied to live PG over the TCP proxy. Additive +
   idempotent: creates `users` (+`password_hash`) / `user_identities` / `sessions`, partial unique
   index on `lower(email)`, owner FKs, owner indexes. Destructive only in that it deletes the
   legacy `DEV_USER_ID` rows (fresh-start policy, approved). **7 legacy test tasks removed.**
2. **Backend env** — `BACKEND_JWT_PRIVATE_KEY` already set on Railway. `APPLE_NATIVE_AUD` /
   `APPLE_WEB_AUD` are now unused (harmless; can be removed).
3. **Deploy** — `railway up --ci --service backend` then `--service powersync`, **from repo root**.
4. **Verified live** — register → login (same `user_id`) → wrong password 401 → JWKS serves →
   `GET /api/auth/token` mints a JWT with `sub=user_id, aud=powersync` → `/api/capture` creates an
   owner-scoped row → PowerSync `/sync/stream` returns an owner-scoped bucket containing only that
   user's task. Verification accounts cleaned up afterwards (DB back to 0 users / 0 tasks).
5. **Clients** — Mac release on tag `mac-v0.2.0` (notarised + Sparkle appcast); iOS to TestFlight
   via the `release-ios.yml` workflow_dispatch. Web bundle is static (no live host configured yet).

## Verify after a redeploy

```bash
BE=https://backend-production-de2f.up.railway.app
EMAIL="you+test@example.com"
# register
curl -s -X POST $BE/api/auth/register -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"a-long-password\"}"
# login returns the SAME user_id
curl -s -X POST $BE/api/auth/login -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"a-long-password\"}"
# wrong password -> generic 401
curl -s -X POST $BE/api/auth/login -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"wrong\"}"
```

Then on a client: register on one surface, log in with the same credentials on Mac + iOS + web →
shared todos; a second account is fully isolated; sign-out clears the local list.

## Deferred (non-blocking for a single trusted user)

Email verification, web HttpOnly-cookie sessions (localStorage XSS risk accepted while web is still
low-risk), and persistent (Redis/PG) rate-limiting (in-memory is fine for one Railway instance).
`register` reveals email existence via 409 (acceptable for a small user base); `login`, `forgot`,
and code issuance do not enumerate. Social sign-in attaches later via `user_identities` — purely
additive.
