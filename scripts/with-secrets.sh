#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYCHAIN_SERVICE="${CAPTURE_KEYCHAIN_SERVICE:-capture}"

usage() {
  printf 'Usage: %s <command> [args...]\n' "$(basename "$0")" >&2
  printf 'Loads .env, .env.local, integrations/.env.local, and optional macOS Keychain entries without printing secret values.\n' >&2
}

load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source "$file"
  set +a
}

keychain_value() {
  local account="$1"
  security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$account" -w 2>/dev/null || true
}

load_keychain_defaults() {
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  command -v security >/dev/null 2>&1 || return 0

  local names=(
    RAILWAY_API_TOKEN
    OPENAI_API_KEY
    OBSIDIAN_API_KEY
    GMAIL_IMAP_APP_PASSWORD
    RESEND_API_KEY
    BREVO_API_KEY
    SENDGRID_API_KEY
    POSTMARK_SERVER_TOKEN
    SMTP_URL
    CAPTURE_API_SECRET
    PS_API_TOKEN
    OPENCLAW_AGENT_TOKEN
    GITHUB_OAUTH_CLIENT_SECRET
    OAUTH_STATE_SECRET
  )

  local name current value
  for name in "${names[@]}"; do
    current="$(printenv "$name" || true)"
    [[ -z "$current" ]] || continue
    value="$(keychain_value "$name")"
    [[ -z "$value" ]] || export "$name=$value"
  done
}

normalise_railway_auth_env() {
  # Railway CLI 5.x honours RAILWAY_TOKEN before RAILWAY_API_TOKEN. A stale legacy
  # RAILWAY_TOKEN therefore makes commands look "broken" even when the API token is valid.
  if [[ -n "${RAILWAY_API_TOKEN:-}" ]]; then
    unset RAILWAY_TOKEN
  elif [[ -n "${RAILWAY_TOKEN:-}" ]]; then
    export RAILWAY_API_TOKEN="$RAILWAY_TOKEN"
    unset RAILWAY_TOKEN
  fi
}

if [[ $# -eq 0 ]]; then
  usage
  exit 64
fi

load_env_file "$ROOT_DIR/.env"
load_env_file "$ROOT_DIR/.env.local"
load_env_file "$ROOT_DIR/integrations/.env.local"
if [[ -n "${CAPTURE_SECRETS_ENV:-}" ]]; then
  load_env_file "$CAPTURE_SECRETS_ENV"
fi
load_keychain_defaults
normalise_railway_auth_env

exec "$@"
