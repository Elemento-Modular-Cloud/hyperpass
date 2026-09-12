#!/usr/bin/env bash
# Run a built elp-llm-proxy against a local/dev elpd (see LOCAL_DEV.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
PROXY_BIN="${BUILD_DIR}/bin/elp-llm-proxy"
ELP_SOCKET="${ELP_SOCKET:-/tmp/elp.socket}"
# OpenAI /v1 on Ollama's default port. Bind localhost + VM gateway.
ELP_LLM_PROXY_LISTEN="${ELP_LLM_PROXY_LISTEN:-127.0.0.1,192.168.67.1:11434}"
VERBOSITY="${VERBOSITY:-info}"
ACTION=start
WAIT_GATEWAY_SECS="${WAIT_GATEWAY_SECS:-30}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- <extra elp-llm-proxy args>]

Start the OpenAI LLM proxy against a local elpd. Prefer running
scripts/run-dev-daemon.sh first. HTTP on :11434 by default.

Options:
  --stop              Stop a running elp-llm-proxy started from this build tree
  --build-dir DIR     Build directory (default: ${BUILD_DIR})
  --listen ADDR       HTTP listen host[,host…]:port (default: ${ELP_LLM_PROXY_LISTEN})
  --verbosity LEVEL   Log level (default: ${VERBOSITY})
  -h, --help          Show this help

Environment:
  BUILD_DIR
  ELP_SOCKET            Used to set ELP_SERVER_ADDRESS=unix:\$SOCKET
  ELP_SERVER_ADDRESS    Override daemon address entirely
  ELP_LLM_PROXY_LISTEN
  WAIT_GATEWAY_SECS     Seconds to wait for non-loopback listen IPs (default: 30)
  VERBOSITY

Examples:
  $(basename "$0")
  curl http://127.0.0.1:11434/healthz
  curl -H "Authorization: Bearer sk-elp-…" http://127.0.0.1:11434/v1/models
EOF
}

stop_dev_proxy() {
  echo "==> Stopping dev elp-llm-proxy (if any)"
  if [[ -x "$PROXY_BIN" ]]; then
    pkill -f "$PROXY_BIN" 2>/dev/null || true
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
    echo "==> Waiting up to ${timeout_secs}s for ${host} (start elpd / bring up the VM bridge)"
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
      echo "    warning: ${host} not found yet; elp-llm-proxy will keep retrying the bind" >&2
    fi
  done
}

EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop) ACTION=stop; shift ;;
    --build-dir) BUILD_DIR="$2"; PROXY_BIN="${BUILD_DIR}/bin/elp-llm-proxy"; shift 2 ;;
    --listen) ELP_LLM_PROXY_LISTEN="$2"; shift 2 ;;
    --verbosity) VERBOSITY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$ACTION" == stop ]]; then
  stop_dev_proxy
  exit 0
fi

if [[ ! -x "$PROXY_BIN" ]]; then
  echo "error: elp-llm-proxy not found at ${PROXY_BIN}" >&2
  echo "       Build with ELP_ENABLE_API=ON (default)." >&2
  exit 1
fi

if [[ -z "${ELP_SERVER_ADDRESS:-}" ]]; then
  export ELP_SERVER_ADDRESS="unix:${ELP_SOCKET}"
fi

echo "==> Dev elp-llm-proxy"
echo "    binary:  ${PROXY_BIN}"
echo "    listen:  http://${ELP_LLM_PROXY_LISTEN}"
echo "    daemon:  ${ELP_SERVER_ADDRESS}"
wait_for_listen_hosts "$ELP_LLM_PROXY_LISTEN" "$WAIT_GATEWAY_SECS"
echo
echo "    Stop:    Ctrl-C, or: $(basename "$0") --stop"
echo

exec "$PROXY_BIN" \
  --listen "$ELP_LLM_PROXY_LISTEN" \
  --verbosity "$VERBOSITY" \
  "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
