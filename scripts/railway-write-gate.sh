#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/railway-write-gate.sh status
  scripts/railway-write-gate.sh freeze --confirm-freeze
  scripts/railway-write-gate.sh unfreeze --confirm-unfreeze
EOF
}

die() {
  printf 'railway-write-gate: %s\n' "$*" >&2
  exit 1
}

: "${RAILWAY_API_TOKEN:?Load RAILWAY_API_TOKEN before changing Railway}"
: "${RAILWAY_PROJECT_ID:?Load RAILWAY_PROJECT_ID before changing Railway}"

command -v railway >/dev/null 2>&1 || die "railway CLI is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

action="${1:-}"
confirmation="${2:-}"
environment="${RAILWAY_ENVIRONMENT:-production}"
region="${RAILWAY_REGION:-eu-west}"

scale_service() {
  local service="$1"
  local replicas="$2"
  railway scale \
    -p "$RAILWAY_PROJECT_ID" \
    -e "$environment" \
    -s "$service" \
    "${region}=${replicas}"
}

case "$action" in
  status)
    backend_status="$(railway service status \
      --project "$RAILWAY_PROJECT_ID" \
      --environment "$environment" \
      --service backend \
      --json)"
    worker_status="$(railway service status \
      --project "$RAILWAY_PROJECT_ID" \
      --environment "$environment" \
      --service worker \
      --json)"
    jq -n --argjson backend "$backend_status" --argjson worker "$worker_status" \
      '{backend: $backend, worker: $worker}'
    ;;
  freeze)
    [[ "$confirmation" == "--confirm-freeze" ]] || die "freeze requires --confirm-freeze"
    scale_service backend 0
    scale_service worker 0
    printf 'Railway backend and worker are scaled to zero; PowerSync remains available for reads.\n'
    ;;
  unfreeze)
    [[ "$confirmation" == "--confirm-unfreeze" ]] || die "unfreeze requires --confirm-unfreeze"
    scale_service backend 1
    scale_service worker 1
    printf 'Railway backend and worker are scaled to one replica.\n'
    ;;
  *)
    usage
    exit 64
    ;;
esac
