#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  printf 'Usage: %s --output-dir DIR\n' "$(basename "$0")" >&2
}

die() {
  printf 'railway-postgres-export: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

output_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

[[ -n "$output_dir" ]] || {
  usage
  exit 64
}

: "${RAILWAY_API_TOKEN:?Load RAILWAY_API_TOKEN before exporting}"
: "${RAILWAY_PROJECT_ID:?Load RAILWAY_PROJECT_ID before exporting}"

for command_name in railway jq docker shasum; do
  require_command "$command_name"
done

railway_environment="${RAILWAY_ENVIRONMENT:-production}"
railway_service="${RAILWAY_POSTGRES_SERVICE:-postgres}"
variables="$(railway variable list \
  --project "$RAILWAY_PROJECT_ID" \
  --environment "$railway_environment" \
  --service "$railway_service" \
  --json)"

pg_host="$(jq -er '.RAILWAY_TCP_PROXY_DOMAIN | select(length > 0)' <<<"$variables")"
pg_port="$(jq -er '.RAILWAY_TCP_PROXY_PORT | select(length > 0)' <<<"$variables")"
pg_user="$(jq -er '.POSTGRES_USER | select(length > 0)' <<<"$variables")"
pg_database="$(jq -er '.POSTGRES_DB | select(length > 0)' <<<"$variables")"
pg_password="$(jq -er '.POSTGRES_PASSWORD | select(length > 0)' <<<"$variables")"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
dump_file="$output_dir/capture-railway-${timestamp}.dump"
manifest_file="$output_dir/capture-railway-${timestamp}.manifest"
dump_partial="${dump_file}.partial"
manifest_partial="${manifest_file}.partial"
manifest_container="capture-manifest-$(date -u +%Y%m%d%H%M%S)-$$"

umask 077
mkdir -p "$output_dir"

cleanup() {
  [[ -z "$manifest_container" ]] || docker rm -f "$manifest_container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

PGCONNECT_TIMEOUT=15 \
PGSSLMODE=disable \
PGPASSWORD="$pg_password" \
docker run --rm \
  -e PGCONNECT_TIMEOUT \
  -e PGSSLMODE \
  -e PGPASSWORD \
  "${POSTGRES_TOOLS_IMAGE:-postgres:18}" \
  pg_dump \
    --format=custom \
    --serializable-deferrable \
    --no-owner \
    --no-privileges \
    -h "$pg_host" \
    -p "$pg_port" \
    -U "$pg_user" \
    -d "$pg_database" >"$dump_partial"

docker run --rm -i "${POSTGRES_TOOLS_IMAGE:-postgres:18}" pg_restore --list <"$dump_partial" >/dev/null

docker run --rm -d \
  --name "$manifest_container" \
  -e POSTGRES_PASSWORD=placeholder \
  -e POSTGRES_DB=postgres \
  "${POSTGRES_TOOLS_IMAGE:-postgres:18}" \
  -c wal_level=logical >/dev/null

for attempt in $(seq 1 60); do
  if docker exec "$manifest_container" pg_isready -U postgres -d postgres >/dev/null 2>&1; then
    break
  fi
  sleep 1
  [[ "$attempt" != 60 ]] || die "temporary manifest database did not become ready"
done

docker exec -i "$manifest_container" pg_restore \
  --exit-on-error \
  --no-owner \
  --no-privileges \
  -U postgres \
  -d postgres <"$dump_partial"

docker exec -i "$manifest_container" psql \
  -X \
  -q \
  -v ON_ERROR_STOP=1 \
  -U postgres \
  -d postgres <"$ROOT_DIR/scripts/sql/production-manifest.sql" >"$manifest_partial"

docker stop "$manifest_container" >/dev/null
manifest_container=""

mv -f "$manifest_partial" "$manifest_file"
mv -f "$dump_partial" "$dump_file"
(
  cd "$output_dir"
  shasum -a 256 "$(basename "$dump_file")" >"$(basename "$dump_file").sha256"
  shasum -a 256 "$(basename "$manifest_file")" >"$(basename "$manifest_file").sha256"
)

printf 'DUMP=%s\nMANIFEST=%s\n' "$dump_file" "$manifest_file"
