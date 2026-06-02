#!/usr/bin/env bash
#
# Expose the Capture stack on the tailnet over HTTPS with a single origin.
#
# Tailscale Serve terminates TLS using your tailnet's MagicDNS cert
# (https://<host>.<tailnet>.ts.net) and reverse-proxies to the local stack.
# We path-route so backend and PowerSync share one HTTPS origin:
#
#   https://<host>.<tailnet>.ts.net/api/...  -> backend connector  (:6060)
#   https://<host>.<tailnet>.ts.net/...      -> PowerSync service  (:8080)
#
# The two services never collide on paths: the backend only serves /api/*,
# PowerSync serves /sync/*, /write-checkpoint*, /probes/*, etc.
#
# Clients then point at a single host:
#   web:    VITE_BACKEND_URL=https://<host>.<tailnet>.ts.net
#           VITE_POWERSYNC_URL=https://<host>.<tailnet>.ts.net
#   native: CaptureConfig.selfHosted(host: "<host>.<tailnet>.ts.net")
#
# Usage:  ./tailscale-serve.sh            # serve to the tailnet (default)
#         FUNNEL=1 ./tailscale-serve.sh   # ALSO expose publicly via Funnel (use with care)
#
# Requires: Tailscale logged in (`tailscale up`) and HTTPS/MagicDNS enabled for the tailnet.
set -euo pipefail

TS="$(command -v tailscale || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"
BACKEND_PORT="${BACKEND_PORT:-6060}"
PS_PORT="${PS_PORT:-8080}"

echo "Resetting existing serve config..."
"$TS" serve reset || true

# PowerSync at the root path.
"$TS" serve --bg --https=443 --set-path / "http://127.0.0.1:${PS_PORT}"
# Backend connector under /api (more specific path wins).
"$TS" serve --bg --https=443 --set-path /api "http://127.0.0.1:${BACKEND_PORT}/api"

if [[ "${FUNNEL:-0}" == "1" ]]; then
  echo "Enabling public Funnel on :443 (internet-reachable)..."
  "$TS" funnel --bg 443 on
fi

echo
echo "Serve status:"
"$TS" serve status
echo
echo "Your Capture origin: https://$("$TS" status --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')"
