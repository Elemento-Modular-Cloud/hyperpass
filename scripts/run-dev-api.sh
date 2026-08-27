#!/usr/bin/env bash
# Run a built hyperpass-api against a local/dev hyperpassd (see LOCAL_DEV.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
API_BIN="${BUILD_DIR}/bin/hyperpass-api"
HYPERPASS_SOCKET="${HYPERPASS_SOCKET:-/tmp/hyperpass.socket}"
HYPERPASS_API_LISTEN="${HYPERPASS_API_LISTEN:-127.0.0.1:51052}"
HYPERPASS_API_TOKEN="${HYPERPASS_API_TOKEN:-}"
INSECURE=0
VERBOSITY="${VERBOSITY:-info}"
ACTION=start

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- <extra hyperpass-api args>]

Start the REST API sidecar against a local hyperpassd. Prefer running
scripts/run-dev-daemon.sh first.

Options:
  --stop              Stop a running hyperpass-api started from this build tree
  --build-dir DIR     Build directory (default: ${BUILD_DIR})
  --listen ADDR       HTTP listen host:port (default: ${HYPERPASS_API_LISTEN})
  --token TOKEN       Bearer API token (or set HYPERPASS_API_TOKEN)
  --insecure-no-auth  Disable REST auth (local development only)
  --verbosity LEVEL   Log level (default: ${VERBOSITY})
  -h, --help          Show this help

Environment:
  BUILD_DIR
  HYPERPASS_SOCKET            Used to set HYPERPASS_SERVER_ADDRESS=unix:\$SOCKET
  HYPERPASS_SERVER_ADDRESS    Override daemon address entirely
  HYPERPASS_API_LISTEN
  HYPERPASS_API_TOKEN
  VERBOSITY

Examples:
  $(basename "$0") --insecure-no-auth
  $(basename "$0") --token secret
  curl -H "Authorization: Bearer secret" http://127.0.0.1:51052/v1/instances
EOF
}

stop_dev_api() {
  echo "==> Stopping dev hyperpass-api (if any)"
  if [[ -x "$API_BIN" ]]; then
    pkill -f "$API_BIN" 2>/dev/null || true
  fi
}

EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop) ACTION=stop; shift ;;
    --build-dir) BUILD_DIR="$2"; API_BIN="${BUILD_DIR}/bin/hyperpass-api"; shift 2 ;;
    --listen) HYPERPASS_API_LISTEN="$2"; shift 2 ;;
    --token) HYPERPASS_API_TOKEN="$2"; shift 2 ;;
    --insecure-no-auth) INSECURE=1; shift ;;
    --verbosity) VERBOSITY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$ACTION" == stop ]]; then
  stop_dev_api
  exit 0
fi

if [[ ! -x "$API_BIN" ]]; then
  echo "error: hyperpass-api not found at ${API_BIN}" >&2
  echo "       Build with HYPERPASS_ENABLE_API=ON (default)." >&2
  exit 1
fi

if [[ -z "${HYPERPASS_SERVER_ADDRESS:-}" ]]; then
  export HYPERPASS_SERVER_ADDRESS="unix:${HYPERPASS_SOCKET}"
fi

AUTH_ARGS=()
if [[ "$INSECURE" -eq 1 ]]; then
  AUTH_ARGS+=(--insecure-no-auth)
elif [[ -n "$HYPERPASS_API_TOKEN" ]]; then
  AUTH_ARGS+=(--api-token "$HYPERPASS_API_TOKEN")
else
  echo "error: provide --token / HYPERPASS_API_TOKEN or --insecure-no-auth" >&2
  exit 1
fi

echo "==> Dev hyperpass-api"
echo "    binary:  ${API_BIN}"
echo "    listen:  http://${HYPERPASS_API_LISTEN}"
echo "    daemon:  ${HYPERPASS_SERVER_ADDRESS}"
echo
echo "    Stop:    Ctrl-C, or: $(basename "$0") --stop"
echo

exec "$API_BIN" \
  --listen "$HYPERPASS_API_LISTEN" \
  --verbosity "$VERBOSITY" \
  "${AUTH_ARGS[@]}" \
  "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
