#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/railway-write-gate.sh status
  scripts/railway-write-gate.sh freeze --confirm-freeze
  scripts/railway-write-gate.sh unfreeze --confirm-unfreeze
  scripts/railway-write-gate.sh pause-all --confirm-pause-all
  scripts/railway-write-gate.sh resume-all --confirm-resume-all
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

service_status() {
  railway service status \
    --project "$RAILWAY_PROJECT_ID" \
    --environment "$environment" \
    --service "$1" \
    --json
}

case "$action" in
  status)
    backend_status="$(service_status backend)"
    worker_status="$(service_status worker)"
    web_status="$(service_status web)"
    powersync_status="$(service_status powersync)"
    postgres_status="$(service_status postgres)"
    jq -n \
      --argjson backend "$backend_status" \
      --argjson worker "$worker_status" \
      --argjson web "$web_status" \
      --argjson powersync "$powersync_status" \
      --argjson postgres "$postgres_status" \
      '{backend: $backend, worker: $worker, web: $web, powersync: $powersync, postgres: $postgres}'
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
  pause-all)
    [[ "$confirmation" == "--confirm-pause-all" ]] || die "pause-all requires --confirm-pause-all"
    scale_service backend 0
    scale_service worker 0
    scale_service web 0
    scale_service powersync 0
    scale_service postgres 0
    printf 'All Railway services are scaled to zero; the Postgres volume is retained.\n'
    ;;
  resume-all)
    [[ "$confirmation" == "--confirm-resume-all" ]] || die "resume-all requires --confirm-resume-all"
    scale_service postgres 1
    scale_service backend 1
    scale_service powersync 1
    scale_service worker 1
    scale_service web 1
    printf 'All Railway services are scaled to one replica.\n'
    ;;
  *)
    usage
    exit 64
    ;;
esac
