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
    RAILWAY_PROJECT_ID
    PG_DATABASE_PASSWORD
    BACKEND_JWT_PRIVATE_KEY
    OPENAI_API_KEY
    OPENAI_BASE_URL
    SENTRY_DSN
    SENTRY_ENVIRONMENT
    SENTRY_TRACES_SAMPLE_RATE
    VITE_SENTRY_DSN
    VITE_SENTRY_ENVIRONMENT
    OBSIDIAN_API_KEY
    GMAIL_IMAP_APP_PASSWORD
    RESEND_API_KEY
    BREVO_API_KEY
    SENDGRID_API_KEY
    POSTMARK_SERVER_TOKEN
    SMTP_URL
    CAPTURE_API_SECRET
    PS_API_TOKEN
    CAPTURE_WEB_SEARCH_API_KEY
    LOCAL_HARNESS_ENABLED
    LOCAL_HARNESS_KIND
    LOCAL_HARNESS_COMMAND
    LOCAL_HARNESS_WORKDIR
    LOCAL_HARNESS_ARGS_JSON
    LOCAL_HARNESS_AGENT
    LOCAL_HARNESS_THINKING
    LOCAL_HARNESS_DEVICE_ID
    LOCAL_HARNESS_DEVICE_NAME
    GITHUB_OAUTH_CLIENT_SECRET
    OAUTH_STATE_SECRET
  )

  local name current value
  for name in "${names[@]}"; do
    current="$(printenv "$name" || true)"
    if [[ "${CAPTURE_KEYCHAIN_OVERRIDE:-0}" != "1" && -n "$current" ]]; then
      continue
    fi
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

connect_custom_railway_postgres() {
  command -v psql >/dev/null 2>&1 || {
    printf 'psql is required for custom Railway Postgres connections.\n' >&2
    exit 127
  }
  command -v jq >/dev/null 2>&1 || {
    printf 'jq is required to read Railway Postgres connection variables.\n' >&2
    exit 127
  }

  local vars pg_host pg_port pg_user pg_database pg_password
  vars="$(railway variable list --service postgres --json)"
  pg_host="$(jq -r '.RAILWAY_TCP_PROXY_DOMAIN // empty' <<<"$vars")"
  pg_port="$(jq -r '.RAILWAY_TCP_PROXY_PORT // empty' <<<"$vars")"
  pg_user="$(jq -r '.POSTGRES_USER // empty' <<<"$vars")"
  pg_database="$(jq -r '.POSTGRES_DB // empty' <<<"$vars")"
  pg_password="$(jq -r '.POSTGRES_PASSWORD // empty' <<<"$vars")"

  if [[ -z "$pg_host" || -z "$pg_port" || -z "$pg_user" || -z "$pg_database" || -z "$pg_password" ]]; then
    printf 'Railway postgres service is missing TCP proxy or Postgres credentials.\n' >&2
    exit 1
  fi

  PGSSLMODE="${PGSSLMODE:-disable}" \
    PGPASSWORD="$pg_password" \
    exec psql -h "$pg_host" -p "$pg_port" -U "$pg_user" -d "$pg_database" "$@"
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

if [[ "$1" == "railway" && "${2:-}" == "connect" && "${3:-}" == "postgres" ]]; then
  shift 3
  connect_custom_railway_postgres "$@"
fi

exec "$@"
