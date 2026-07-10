#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
  printf 'mac-mini-worker: %s\n' "$*" >&2
  exit 1
}

uri_encode() {
  node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$1"
}

command -v node >/dev/null 2>&1 || die "node is required"
command -v npm >/dev/null 2>&1 || die "npm is required"

: "${PG_DATABASE_PASSWORD:?Load PG_DATABASE_PASSWORD from the capture Keychain}"

PG_DATABASE_NAME="${PG_DATABASE_NAME:-postgres}"
PG_DATABASE_USER="${PG_DATABASE_USER:-postgres}"
PG_HOST_PORT="${PG_HOST_PORT:-5432}"

encoded_user="$(uri_encode "$PG_DATABASE_USER")"
encoded_password="$(uri_encode "$PG_DATABASE_PASSWORD")"
encoded_database="$(uri_encode "$PG_DATABASE_NAME")"

export WORKER_DATABASE_URI="postgresql://${encoded_user}:${encoded_password}@127.0.0.1:${PG_HOST_PORT}/${encoded_database}"
export NODE_ENV=production
export SENTRY_ENVIRONMENT=production
export CAPTURE_WORK_ROOT="${CAPTURE_WORK_ROOT:-$HOME/work}"
export LOCAL_HARNESS_WORKDIR="${LOCAL_HARNESS_WORKDIR:-$HOME/work}"

cd "$ROOT_DIR/worker"
exec npm start
