#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose --profile production)
STACK_LABEL="dev.crmitchelmore.capture.stack"
BACKUP_LABEL="dev.crmitchelmore.capture.backup"
WORKER_LABEL="dev.crmitchelmore.capture.worker"
STACK_SERVICES=(pg-db backend powersync web capture-edge)

usage() {
  cat >&2 <<'EOF'
Usage: scripts/mac-mini.sh <command> [args]

Commands:
  bootstrap               Install/start the local container runtime.
  deploy                  Build and start the production stack.
  start                   Start the existing production stack without rebuilding.
  health                  Verify the local production edge and services.
  tailscale-private       Publish port 10000 to the tailnet only.
  tailscale-public --confirm-public
                          Switch port 10000 to Tailscale Funnel.
  tailscale-status        Show only Capture's port-10000 exposure.
  backup                  Create and verify a source-database backup.
  restore --dump FILE --manifest FILE --confirm-restore
                          Replace local source data with a verified Railway dump.
  install-launchd         Install the stack watchdog and nightly backup agents.
EOF
}

die() {
  printf 'mac-mini: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

compose() {
  (cd "$ROOT_DIR" && "${COMPOSE[@]}" "$@")
}

uri_encode() {
  node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$1"
}

tailscale_dns_name() {
  require_command tailscale
  require_command jq
  local dns_name
  dns_name="$(tailscale status --json | jq -er '.Self.DNSName | select(length > 0)')"
  printf '%s' "${dns_name%.}"
}

configure_runtime() {
  require_command node

  export CAPTURE_BIND_HOST="${CAPTURE_BIND_HOST:-127.0.0.1}"
  export CAPTURE_EDGE_PORT="${CAPTURE_EDGE_PORT:-10000}"

  local dns_name origin encoded_user encoded_password encoded_database
  dns_name="${CAPTURE_TAILSCALE_DNS_NAME:-$(tailscale_dns_name)}"
  origin="${CAPTURE_PUBLIC_ORIGIN:-https://${dns_name}:${CAPTURE_EDGE_PORT}}"

  export CAPTURE_PUBLIC_ORIGIN="$origin"
  export PUBLIC_WEB_ORIGIN="$origin"
  export PUBLIC_BACKEND_ORIGIN="$origin"
  export POWERSYNC_PUBLIC_URL="$origin"
  export VITE_BACKEND_URL="$origin"
  export VITE_POWERSYNC_URL="$origin"
  export WEBAUTHN_RP_ID="${CAPTURE_WEBAUTHN_RP_ID:-$dns_name}"
  export WEBAUTHN_RP_NAME="${WEBAUTHN_RP_NAME:-Capture}"
  export NODE_ENV=production
  export SENTRY_ENVIRONMENT=production
  export VITE_SENTRY_ENVIRONMENT=production
  export CAPTURE_WORK_ROOT="${CAPTURE_WORK_ROOT:-$HOME/work}"
  export LOCAL_HARNESS_WORKDIR="${LOCAL_HARNESS_WORKDIR:-$HOME/work}"

  export PG_DATABASE_NAME="${PG_DATABASE_NAME:-postgres}"
  export PG_DATABASE_PORT="${PG_DATABASE_PORT:-5432}"
  export PG_HOST_PORT="${PG_HOST_PORT:-$PG_DATABASE_PORT}"
  export PG_DATABASE_USER="${PG_DATABASE_USER:-postgres}"
  export BACKEND_PORT="${BACKEND_PORT:-6060}"
  export BACKEND_HOST_PORT="${BACKEND_HOST_PORT:-$BACKEND_PORT}"
  export PS_PORT="${PS_PORT:-8080}"
  export PS_HOST_PORT="${PS_HOST_PORT:-$PS_PORT}"
  export JWT_ISSUER="${JWT_ISSUER:-capture}"
  export JWT_AUDIENCE="${JWT_AUDIENCE:-powersync}"
  export DEV_USER_ID="${DEV_USER_ID:-00000000-0000-0000-0000-000000000001}"

  encoded_user="$(uri_encode "$PG_DATABASE_USER")"
  encoded_password="$(uri_encode "${PG_DATABASE_PASSWORD:-}")"
  encoded_database="$(uri_encode "$PG_DATABASE_NAME")"
  export BACKEND_DATABASE_URI="postgresql://${encoded_user}:${encoded_password}@pg-db:${PG_DATABASE_PORT}/${encoded_database}"
  export PS_DATA_SOURCE_URI="$BACKEND_DATABASE_URI"
  export PS_STORAGE_URI="postgresql://${encoded_user}:${encoded_password}@pg-db:${PG_DATABASE_PORT}/powersync"
  export PS_JWKS_URL="http://backend:${BACKEND_PORT}/api/auth/keys"
}

require_production_secrets() {
  local name value
  for name in PG_DATABASE_PASSWORD CAPTURE_API_SECRET PS_API_TOKEN BACKEND_JWT_PRIVATE_KEY; do
    value="${!name:-}"
    [[ -n "$value" ]] || die "$name is required; load it from the capture Keychain"
    case "$value" in
      placeholder|local-dev-password|use_a_better_token_in_production)
        die "$name still contains a development placeholder"
        ;;
    esac
  done
}

ensure_colima() {
  require_command colima
  require_command docker
  if ! docker info >/dev/null 2>&1; then
    colima start \
      --cpu "${COLIMA_CPU:-4}" \
      --memory "${COLIMA_MEMORY_GB:-8}" \
      --disk "${COLIMA_DISK_GB:-30}" \
      --vm-type vz \
      --mount-type virtiofs
  fi
  docker info >/dev/null
  docker compose version >/dev/null
}

bootstrap() {
  [[ "$(uname -s)" == "Darwin" ]] || die "bootstrap is supported only on macOS"
  require_command brew

  HOMEBREW_NO_AUTO_UPDATE=1 brew install colima docker docker-compose jq node@22

  local plugin
  plugin="$(brew --prefix)/lib/docker/cli-plugins/docker-compose"
  if [[ -x "$plugin" && ! -e "$HOME/.docker/cli-plugins/docker-compose" ]]; then
    mkdir -p "$HOME/.docker/cli-plugins"
    ln -s "$plugin" "$HOME/.docker/cli-plugins/docker-compose"
  fi

  ensure_colima
  printf 'Container runtime ready.\n'
}

wait_for_url() {
  local url="$1"
  local attempts="${2:-60}"
  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent --show-error --max-time 5 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  die "timed out waiting for $url"
}

health() {
  configure_runtime
  ensure_colima

  compose ps "${STACK_SERVICES[@]}"
  wait_for_url "http://127.0.0.1:${CAPTURE_EDGE_PORT}/"
  wait_for_url "http://127.0.0.1:${CAPTURE_EDGE_PORT}/api/health"
  wait_for_url "http://127.0.0.1:${CAPTURE_EDGE_PORT}/api/auth/keys"
  wait_for_url "http://127.0.0.1:${CAPTURE_EDGE_PORT}/probes/liveness"

  curl --fail --silent "http://127.0.0.1:${CAPTURE_EDGE_PORT}/api/health" | jq -e '.ok == true' >/dev/null
  curl --fail --silent "http://127.0.0.1:${CAPTURE_EDGE_PORT}/api/auth/keys" | jq -e '.keys | length > 0' >/dev/null
  curl --fail --silent "http://127.0.0.1:${CAPTURE_EDGE_PORT}/probes/liveness" | jq -e '.ready == true' >/dev/null
  printf 'Capture production edge is healthy at %s.\n' "$CAPTURE_PUBLIC_ORIGIN"
}

start_stack() {
  local build="$1"
  configure_runtime
  require_production_secrets
  ensure_colima

  compose config --quiet
  compose stop worker >/dev/null 2>&1 || true
  local args=(up -d --remove-orphans)
  [[ "$build" == "1" ]] && args+=(--build)
  args+=("${STACK_SERVICES[@]}")
  compose "${args[@]}"
  if [[ "$build" == "1" ]]; then
    (cd "$ROOT_DIR/worker" && npm ci --include=dev)
  fi
  health
}

protected_tailscale_config() {
  tailscale serve status --json | jq -cS '
    {
      TCP: ((.TCP // {}) | with_entries(select(.key != "10000"))),
      Web: ((.Web // {}) | with_entries(select(.key | endswith(":10000") | not))),
      AllowFunnel: ((.AllowFunnel // {}) | with_entries(select(.key | endswith(":10000") | not)))
    }
  '
}

configure_tailscale() {
  local mode="$1"
  configure_runtime
  require_command tailscale
  require_command jq

  local before after target
  before="$(protected_tailscale_config)"
  target="http://127.0.0.1:${CAPTURE_EDGE_PORT}"

  case "$mode" in
    private)
      tailscale serve --bg --https="${CAPTURE_EDGE_PORT}" --yes "$target"
      ;;
    public)
      tailscale funnel --bg --https="${CAPTURE_EDGE_PORT}" --yes "$target"
      ;;
    *)
      die "unknown Tailscale mode: $mode"
      ;;
  esac

  after="$(protected_tailscale_config)"
  [[ "$before" == "$after" ]] || die "existing Tailscale services changed; inspect 'tailscale serve status'"

  wait_for_url "${CAPTURE_PUBLIC_ORIGIN}/api/health"
  printf 'Capture is available in %s mode at %s.\n' "$mode" "$CAPTURE_PUBLIC_ORIGIN"
}

tailscale_status() {
  configure_runtime
  tailscale serve status --json | jq --arg suffix ":${CAPTURE_EDGE_PORT}" '
    {
      TCP: (.TCP["10000"] // null),
      Web: ((.Web // {}) | with_entries(select(.key | endswith($suffix)))),
      AllowFunnel: ((.AllowFunnel // {}) | with_entries(select(.key | endswith($suffix))))
    }
  '
}

backup() {
  configure_runtime
  require_production_secrets
  ensure_colima

  local backup_dir timestamp partial final
  backup_dir="${CAPTURE_BACKUP_DIR:-$HOME/Library/Application Support/Capture/backups}"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  partial="$backup_dir/.capture-postgres-${timestamp}.dump.partial"
  final="$backup_dir/capture-postgres-${timestamp}.dump"

  umask 077
  mkdir -p "$backup_dir"
  compose exec -T pg-db pg_dump \
    -Fc \
    --no-owner \
    --no-privileges \
    -U "$PG_DATABASE_USER" \
    -d "$PG_DATABASE_NAME" >"$partial"
  compose exec -T pg-db pg_restore --list <"$partial" >/dev/null
  mv -f "$partial" "$final"
  (
    cd "$backup_dir"
    shasum -a 256 "$(basename "$final")" >"$(basename "$final").sha256"
  )

  printf '%s\n' "$final"
}

validate_identifier() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "invalid PostgreSQL identifier: $1"
}

restore() {
  local dump_file=""
  local source_manifest=""
  local confirmed="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dump)
        dump_file="${2:-}"
        shift 2
        ;;
      --manifest)
        source_manifest="${2:-}"
        shift 2
        ;;
      --confirm-restore)
        confirmed="1"
        shift
        ;;
      *)
        die "unknown restore argument: $1"
        ;;
    esac
  done

  [[ "$confirmed" == "1" ]] || die "restore requires --confirm-restore"
  [[ -f "$dump_file" ]] || die "dump file not found: $dump_file"
  [[ -f "$source_manifest" ]] || die "source manifest not found: $source_manifest"

  configure_runtime
  require_production_secrets
  ensure_colima
  validate_identifier "$PG_DATABASE_USER"
  validate_identifier "$PG_DATABASE_NAME"

  compose exec -T pg-db pg_restore --list <"$dump_file" >/dev/null
  local worker_was_loaded="0"
  if launchctl print "gui/$UID/$WORKER_LABEL" >/dev/null 2>&1; then
    worker_was_loaded="1"
    launchctl disable "gui/$UID/$WORKER_LABEL"
    launchctl kill SIGTERM "gui/$UID/$WORKER_LABEL" >/dev/null 2>&1 || true
    sleep 2
  fi

  compose stop capture-edge web backend worker powersync

  local pre_restore_backup target_manifest target_partial
  pre_restore_backup="$(backup)"
  printf 'Pre-restore backup: %s\n' "$pre_restore_backup"

  compose exec -T pg-db psql \
    -X \
    -v ON_ERROR_STOP=1 \
    -U "$PG_DATABASE_USER" \
    -d template1 \
    -c "select pg_drop_replication_slot(slot_name) from pg_replication_slots where slot_name like 'powersync%';"

  compose exec -T pg-db psql \
    -X \
    -v ON_ERROR_STOP=1 \
    -U "$PG_DATABASE_USER" \
    -d template1 \
    -c "drop database if exists \"$PG_DATABASE_NAME\" with (force);"
  compose exec -T pg-db psql \
    -X \
    -v ON_ERROR_STOP=1 \
    -U "$PG_DATABASE_USER" \
    -d template1 \
    -c "create database \"$PG_DATABASE_NAME\" owner \"$PG_DATABASE_USER\";"

  compose exec -T pg-db psql \
    -X \
    -v ON_ERROR_STOP=1 \
    -U "$PG_DATABASE_USER" \
    -d template1 \
    -c 'drop database if exists powersync with (force);'
  compose exec -T pg-db psql \
    -X \
    -v ON_ERROR_STOP=1 \
    -U "$PG_DATABASE_USER" \
    -d template1 \
    -c "create database powersync owner \"$PG_DATABASE_USER\";"

  compose exec -T pg-db pg_restore \
    --exit-on-error \
    --no-owner \
    --no-privileges \
    -U "$PG_DATABASE_USER" \
    -d "$PG_DATABASE_NAME" <"$dump_file"

  compose exec -T pg-db psql \
    -X \
    -q \
    -v ON_ERROR_STOP=1 \
    -U "$PG_DATABASE_USER" \
    -d "$PG_DATABASE_NAME" \
    -c 'analyze;'

  target_manifest="${source_manifest%.manifest}.target.manifest"
  target_partial="${target_manifest}.partial"
  compose exec -T pg-db psql \
    -X \
    -q \
    -v ON_ERROR_STOP=1 \
    -U "$PG_DATABASE_USER" \
    -d "$PG_DATABASE_NAME" <"$ROOT_DIR/scripts/sql/production-manifest.sql" >"$target_partial"
  mv -f "$target_partial" "$target_manifest"

  if ! diff -u "$source_manifest" "$target_manifest"; then
    die "source and target manifests differ; services remain stopped"
  fi

  compose exec -T pg-db psql \
    -X \
    -q \
    -v ON_ERROR_STOP=1 \
    -U "$PG_DATABASE_USER" \
    -d "$PG_DATABASE_NAME" <"$ROOT_DIR/scripts/sql/production-integrity.sql"

  start_stack 0
  if [[ "$worker_was_loaded" == "1" ]]; then
    launchctl enable "gui/$UID/$WORKER_LABEL"
    launchctl kickstart -k "gui/$UID/$WORKER_LABEL"
  fi
  printf 'Restore complete and verified. Target manifest: %s\n' "$target_manifest"
}

render_launchd_template() {
  local template="$1"
  local destination="$2"
  local escaped_root escaped_home
  escaped_root="$(printf '%s' "$ROOT_DIR" | sed 's/[&|]/\\&/g')"
  escaped_home="$(printf '%s' "$HOME" | sed 's/[&|]/\\&/g')"
  sed -e "s|__REPO_ROOT__|$escaped_root|g" -e "s|__HOME__|$escaped_home|g" "$template" >"$destination"
}

install_launchd() {
  local launch_agents="$HOME/Library/LaunchAgents"
  local logs="$HOME/Library/Logs/Capture"
  local stack_plist="$launch_agents/${STACK_LABEL}.plist"
  local backup_plist="$launch_agents/${BACKUP_LABEL}.plist"
  local worker_plist="$launch_agents/${WORKER_LABEL}.plist"

  mkdir -p "$launch_agents" "$logs"
  render_launchd_template "$ROOT_DIR/infra/mac-mini/${STACK_LABEL}.plist.template" "$stack_plist"
  render_launchd_template "$ROOT_DIR/infra/mac-mini/${BACKUP_LABEL}.plist.template" "$backup_plist"
  render_launchd_template "$ROOT_DIR/infra/mac-mini/${WORKER_LABEL}.plist.template" "$worker_plist"
  plutil -lint "$stack_plist" "$backup_plist" "$worker_plist"

  launchctl bootout "gui/$UID/$STACK_LABEL" >/dev/null 2>&1 || true
  launchctl bootout "gui/$UID/$BACKUP_LABEL" >/dev/null 2>&1 || true
  launchctl bootout "gui/$UID/$WORKER_LABEL" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$UID" "$stack_plist"
  launchctl bootstrap "gui/$UID" "$backup_plist"
  launchctl bootstrap "gui/$UID" "$worker_plist"
  launchctl enable "gui/$UID/$STACK_LABEL"
  launchctl enable "gui/$UID/$BACKUP_LABEL"
  launchctl enable "gui/$UID/$WORKER_LABEL"
  launchctl kickstart -k "gui/$UID/$STACK_LABEL"
  launchctl kickstart -k "gui/$UID/$WORKER_LABEL"
  printf 'Installed %s, %s and %s.\n' "$STACK_LABEL" "$BACKUP_LABEL" "$WORKER_LABEL"
}

command="${1:-}"
shift || true

case "$command" in
  bootstrap)
    bootstrap
    ;;
  deploy)
    start_stack 1
    ;;
  start)
    start_stack 0
    ;;
  health)
    health
    ;;
  tailscale-private)
    configure_tailscale private
    ;;
  tailscale-public)
    [[ "${1:-}" == "--confirm-public" ]] || die "tailscale-public requires --confirm-public"
    configure_tailscale public
    ;;
  tailscale-status)
    tailscale_status
    ;;
  backup)
    backup
    ;;
  restore)
    restore "$@"
    ;;
  install-launchd)
    install_launchd
    ;;
  *)
    usage
    exit 64
    ;;
esac
