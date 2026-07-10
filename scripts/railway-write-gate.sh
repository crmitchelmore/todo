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

stop_service() {
  local service="$1"
  railway down \
    -p "$RAILWAY_PROJECT_ID" \
    -e "$environment" \
    -s "$service" \
    -y || true
}

service_status() {
  railway service status \
    --project "$RAILWAY_PROJECT_ID" \
    --environment "$environment" \
    --service "$1" \
    --json
}

redeploy_service() {
  railway redeploy \
    -p "$RAILWAY_PROJECT_ID" \
    -e "$environment" \
    -s "$1" \
    -y
}

wait_service_ready() {
  local service="$1"
  local attempt status
  for ((attempt = 1; attempt <= 60; attempt++)); do
    status="$(service_status "$service")"
    if [[ "$(jq -r '.stopped' <<<"$status")" == "false" &&
          "$(jq -r '.status' <<<"$status")" == "SUCCESS" ]]; then
      return 0
    fi
    sleep 5
  done
  die "$service did not become ready"
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
    stop_service backend
    stop_service worker
    printf 'Railway backend and worker deployments are removed; PowerSync remains available for reads.\n'
    ;;
  unfreeze)
    [[ "$confirmation" == "--confirm-unfreeze" ]] || die "unfreeze requires --confirm-unfreeze"
    redeploy_service backend
    redeploy_service worker
    printf 'Railway backend and worker are redeploying.\n'
    ;;
  pause-all)
    [[ "$confirmation" == "--confirm-pause-all" ]] || die "pause-all requires --confirm-pause-all"
    stop_service backend
    stop_service worker
    stop_service web
    stop_service powersync
    stop_service postgres
    printf 'All Railway deployments are removed; the Postgres volume is retained.\n'
    ;;
  resume-all)
    [[ "$confirmation" == "--confirm-resume-all" ]] || die "resume-all requires --confirm-resume-all"
    redeploy_service postgres
    wait_service_ready postgres
    redeploy_service backend
    redeploy_service powersync
    redeploy_service worker
    redeploy_service web
    printf 'All Railway services are redeploying.\n'
    ;;
  *)
    usage
    exit 64
    ;;
esac
