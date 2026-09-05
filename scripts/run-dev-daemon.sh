#!/usr/bin/env bash
# Run a built elpd side-by-side with the system Multipass install (see LOCAL_DEV.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
DAEMON="${BUILD_DIR}/bin/elpd"
ELP_SOCKET="${ELP_SOCKET:-/tmp/elp.socket}"
ELP_STORAGE="${ELP_STORAGE:-/tmp/elp-data}"
ELP_DISTRIBUTIONS_URL="${ELP_DISTRIBUTIONS_URL:-${ROOT}/data/distributions/distribution-info.json}"
VERBOSITY="${VERBOSITY:-debug}"
ACTION=start

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- <extra elpd args>]

Start (or stop) a local elpd from the build tree without replacing the
system Multipass daemon. Uses a separate socket, storage directory, and
distributions catalog by default.

Note: A packaged Electros LaunchPad install already uses distinct defaults from Multipass;
this script is mainly for exercising a build-tree daemon.

Options:
  --stop            Stop a running dev daemon and remove its socket
  --build-dir DIR   Build directory (default: ${BUILD_DIR})
  --verbosity LEVEL elpd --verbosity (default: ${VERBOSITY})
  -h, --help        Show this help

Environment:
  BUILD_DIR                   Build tree (default: ${ROOT}/build)
  ELP_SOCKET            Unix socket path (default: ${ELP_SOCKET})
  ELP_STORAGE           Instance/image storage (default: ${ELP_STORAGE})
  ELP_DISTRIBUTIONS_URL Catalog JSON path or URL
  VERBOSITY                   Log level (default: debug)
  ELP_LLMFIT            Path to llmfit (auto-detected when possible)
  ELP_LLAMA_SERVER      Path to llama-server for GGUF inference

Examples:
  $(basename "$0")
  $(basename "$0") --stop
  $(basename "$0") -- --address unix:/tmp/other.socket
EOF
}

stop_dev_daemon() {
  echo "==> Stopping dev elpd (if any)"
  if [[ -x "$DAEMON" ]]; then
    sudo pkill -9 -f "$DAEMON" 2>/dev/null || true
  fi
  sudo pkill -9 -f "unix:${ELP_SOCKET}" 2>/dev/null || true
  if [[ -e "$ELP_SOCKET" ]]; then
    sudo rm -f "$ELP_SOCKET"
  fi
}

EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop) ACTION=stop; shift ;;
    --build-dir) BUILD_DIR="$2"; DAEMON="${BUILD_DIR}/bin/elpd"; shift 2 ;;
    --verbosity) VERBOSITY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$ACTION" == stop ]]; then
  stop_dev_daemon
  exit 0
fi

if [[ ! -x "$DAEMON" ]]; then
  echo "error: elpd not found at ${DAEMON}" >&2
  echo "       Build first: ./scripts/build-macos.sh  (or build-linux.sh)" >&2
  exit 1
fi

mkdir -p "$ELP_STORAGE"

export ELP_STORAGE
export ELP_DISTRIBUTIONS_URL

resolve_tool() {
  local name="$1"
  local env_var="$2"
  if [[ -n "${!env_var:-}" ]]; then
    echo "${!env_var}"
    return
  fi
  local found=""
  found="$(command -v "$name" 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    echo "$found"
    return
  fi
  for candidate in \
    "/opt/homebrew/bin/${name}" \
    "/usr/local/bin/${name}"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done
}

if [[ -z "${ELP_LLMFIT:-}" ]]; then
  ELP_LLMFIT="$(resolve_tool llmfit ELP_LLMFIT)"
  [[ -n "$ELP_LLMFIT" ]] && export ELP_LLMFIT
fi

if [[ -z "${ELP_LLAMA_SERVER:-}" ]]; then
  ELP_LLAMA_SERVER="$(resolve_tool llama-server ELP_LLAMA_SERVER)"
  [[ -n "$ELP_LLAMA_SERVER" ]] && export ELP_LLAMA_SERVER
fi

echo "==> Dev elpd"
echo "    binary:      ${DAEMON}"
echo "    socket:      unix:${ELP_SOCKET}"
echo "    storage:     ${ELP_STORAGE}"
echo "    catalog:     ${ELP_DISTRIBUTIONS_URL}"
if [[ -n "${ELP_LLMFIT:-}" ]]; then
  echo "    llmfit:      ${ELP_LLMFIT}"
else
  echo "    llmfit:      (not found — catalog suggestions need llmfit on PATH)"
fi
if [[ -n "${ELP_LLAMA_SERVER:-}" ]]; then
  echo "    llama-server:${ELP_LLAMA_SERVER}"
else
  echo "    llama-server:(not found — set ELP_LLAMA_SERVER to load GGUF models)"
fi
echo
echo "    CLI/GUI:     export ELP_SERVER_ADDRESS=unix:${ELP_SOCKET}"
echo "                 export PATH=\"${BUILD_DIR}/bin:\$PATH\""
echo "                 ./scripts/run-dev-gui.sh"
echo
echo "    Stop:        Ctrl-C, or: $(basename "$0") --stop"
echo

if [[ $EUID -eq 0 ]]; then
  exec "$DAEMON" \
    --logger stderr \
    --verbosity "$VERBOSITY" \
    --address "unix:${ELP_SOCKET}" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
else
  exec sudo -E "$DAEMON" \
    --logger stderr \
    --verbosity "$VERBOSITY" \
    --address "unix:${ELP_SOCKET}" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
fi
