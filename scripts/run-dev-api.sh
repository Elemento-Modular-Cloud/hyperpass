#!/usr/bin/env bash
# Run a built hyperpass-api against a local/dev hyperpassd (see LOCAL_DEV.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
API_BIN="${BUILD_DIR}/bin/hyperpass-api"
HYPERPASS_SOCKET="${HYPERPASS_SOCKET:-/tmp/hyperpass.socket}"
# Temporary: matcher VM port. Service/Meson canonical is 7781.
# Bind localhost + VM gateway (not 0.0.0.0) so guests reach https://192.168.67.1:7777.
HYPERPASS_API_LISTEN="${HYPERPASS_API_LISTEN:-127.0.0.1,192.168.67.1:7777}"
HYPERPASS_API_TOKEN="${HYPERPASS_API_TOKEN:-}"
INSECURE=0
HTTP=0
CERT_FILE="${HYPERPASS_API_CERT:-}"
KEY_FILE="${HYPERPASS_API_KEY:-}"
VERBOSITY="${VERBOSITY:-info}"
ACTION=start
WAIT_GATEWAY_SECS="${WAIT_GATEWAY_SECS:-30}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- <extra hyperpass-api args>]

Start the REST API sidecar against a local hyperpassd. Prefer running
scripts/run-dev-daemon.sh first. HTTPS is on by default (AtomOS/Electros).

Options:
  --stop              Stop a running hyperpass-api started from this build tree
  --build-dir DIR     Build directory (default: ${BUILD_DIR})
  --listen ADDR       HTTPS listen host[,host…]:port (default: ${HYPERPASS_API_LISTEN})
  --token TOKEN       Bearer API token (or set HYPERPASS_API_TOKEN)
  --insecure-no-auth  Disable REST auth (local development only)
  --http              Plain HTTP instead of HTTPS (breaks Electros fingerprinting)
  --cert PATH         TLS certificate PEM (or HYPERPASS_API_CERT)
  --key PATH          TLS private key PEM (or HYPERPASS_API_KEY)
  --verbosity LEVEL   Log level (default: ${VERBOSITY})
  -h, --help          Show this help

Environment:
  BUILD_DIR
  HYPERPASS_SOCKET            Used to set HYPERPASS_SERVER_ADDRESS=unix:\$SOCKET
  HYPERPASS_SERVER_ADDRESS    Override daemon address entirely
  HYPERPASS_API_LISTEN
  HYPERPASS_API_TOKEN
  HYPERPASS_API_CERT
  HYPERPASS_API_KEY
  WAIT_GATEWAY_SECS           Seconds to wait for non-loopback listen IPs (default: 30)
  VERBOSITY

Examples:
  $(basename "$0") --token secret
  $(basename "$0") --token secret --cert ./api.crt --key ./api.key
  curl -k https://127.0.0.1:7777/fingerprint
  curl -k -H "Authorization: Bearer secret" https://127.0.0.1:7777/
EOF
}

stop_dev_api() {
  echo "==> Stopping dev hyperpass-api (if any)"
  if [[ -x "$API_BIN" ]]; then
    pkill -f "$API_BIN" 2>/dev/null || true
  fi
}

host_is_local() {
  case "$1" in
    127.0.0.1|0.0.0.0|::1|localhost|"*") return 0 ;;
    *) return 1 ;;
  esac
}

host_is_present() {
  local host="$1"
  if command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | grep -Eq "inet ${host}( |$)" && return 0
  fi
  if command -v ip >/dev/null 2>&1; then
    ip -4 addr show 2>/dev/null | grep -Eq "inet ${host}/" && return 0
  fi
  return 1
}

wait_for_listen_hosts() {
  local listen="$1"
  local timeout_secs="$2"
  local hosts_part="${listen%:*}"
  local host
  local IFS=','

  for host in $hosts_part; do
    host="${host#"${host%%[![:space:]]*}"}"
    host="${host%"${host##*[![:space:]]}"}"
    host="${host#https://}"
    host="${host#http://}"
    if host_is_local "$host"; then
      continue
    fi
    if host_is_present "$host"; then
      echo "    gateway ${host} is up"
      continue
    fi
    echo "==> Waiting up to ${timeout_secs}s for ${host} (start hyperpassd / bring up the VM bridge)"
    local waited=0
    while (( waited < timeout_secs )); do
      if host_is_present "$host"; then
        echo "    gateway ${host} is up"
        break
      fi
      sleep 1
      waited=$((waited + 1))
    done
    if ! host_is_present "$host"; then
      echo "    warning: ${host} not found yet; hyperpass-api will keep retrying the bind" >&2
    fi
  done
}

EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop) ACTION=stop; shift ;;
    --build-dir) BUILD_DIR="$2"; API_BIN="${BUILD_DIR}/bin/hyperpass-api"; shift 2 ;;
    --listen) HYPERPASS_API_LISTEN="$2"; shift 2 ;;
    --token) HYPERPASS_API_TOKEN="$2"; shift 2 ;;
    --insecure-no-auth) INSECURE=1; shift ;;
    --http) HTTP=1; shift ;;
    --https) shift ;; # default; kept for backwards compatibility
    --cert) CERT_FILE="$2"; shift 2 ;;
    --key) KEY_FILE="$2"; shift 2 ;;
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

TLS_ARGS=()
SCHEME=https
if [[ "$HTTP" -eq 1 ]]; then
  SCHEME=http
  TLS_ARGS+=(--http)
fi
if [[ -n "$CERT_FILE" ]]; then
  TLS_ARGS+=(--cert "$CERT_FILE")
fi
if [[ -n "$KEY_FILE" ]]; then
  TLS_ARGS+=(--key "$KEY_FILE")
fi

echo "==> Dev hyperpass-api"
echo "    binary:  ${API_BIN}"
echo "    listen:  ${SCHEME}://${HYPERPASS_API_LISTEN}"
echo "    daemon:  ${HYPERPASS_SERVER_ADDRESS}"
wait_for_listen_hosts "$HYPERPASS_API_LISTEN" "$WAIT_GATEWAY_SECS"
echo
echo "    Stop:    Ctrl-C, or: $(basename "$0") --stop"
echo

exec "$API_BIN" \
  --listen "$HYPERPASS_API_LISTEN" \
  --verbosity "$VERBOSITY" \
  "${AUTH_ARGS[@]}" \
  "${TLS_ARGS[@]+"${TLS_ARGS[@]}"}" \
  "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
