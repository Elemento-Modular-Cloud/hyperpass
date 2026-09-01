#!/usr/bin/env bash
# Run a built hyperpassd side-by-side with the system Multipass install (see LOCAL_DEV.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
DAEMON="${BUILD_DIR}/bin/hyperpassd"
HYPERPASS_SOCKET="${HYPERPASS_SOCKET:-/tmp/hyperpass.socket}"
HYPERPASS_STORAGE="${HYPERPASS_STORAGE:-/tmp/hyperpass-data}"
HYPERPASS_DISTRIBUTIONS_URL="${HYPERPASS_DISTRIBUTIONS_URL:-${ROOT}/data/distributions/distribution-info.json}"
VERBOSITY="${VERBOSITY:-debug}"
ACTION=start

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- <extra hyperpassd args>]

Start (or stop) a local hyperpassd from the build tree without replacing the
system Multipass daemon. Uses a separate socket, storage directory, and
distributions catalog by default.

Note: A packaged Hyperpass install already uses distinct defaults from Multipass;
this script is mainly for exercising a build-tree daemon.

Options:
  --stop            Stop a running dev daemon and remove its socket
  --build-dir DIR   Build directory (default: ${BUILD_DIR})
  --verbosity LEVEL hyperpassd --verbosity (default: ${VERBOSITY})
  -h, --help        Show this help

Environment:
  BUILD_DIR                   Build tree (default: ${ROOT}/build)
  HYPERPASS_SOCKET            Unix socket path (default: ${HYPERPASS_SOCKET})
  HYPERPASS_STORAGE           Instance/image storage (default: ${HYPERPASS_STORAGE})
  HYPERPASS_DISTRIBUTIONS_URL Catalog JSON path or URL
  VERBOSITY                   Log level (default: debug)

Examples:
  $(basename "$0")
  $(basename "$0") --stop
  $(basename "$0") -- --address unix:/tmp/other.socket
EOF
}

stop_dev_daemon() {
  echo "==> Stopping dev hyperpassd (if any)"
  if [[ -x "$DAEMON" ]]; then
    sudo pkill -9 -f "$DAEMON" 2>/dev/null || true
  fi
  sudo pkill -9 -f "unix:${HYPERPASS_SOCKET}" 2>/dev/null || true
  if [[ -e "$HYPERPASS_SOCKET" ]]; then
    sudo rm -f "$HYPERPASS_SOCKET"
  fi
}

EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop) ACTION=stop; shift ;;
    --build-dir) BUILD_DIR="$2"; DAEMON="${BUILD_DIR}/bin/hyperpassd"; shift 2 ;;
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
  echo "error: hyperpassd not found at ${DAEMON}" >&2
  echo "       Build first: ./scripts/build-macos.sh  (or build-linux.sh)" >&2
  exit 1
fi

mkdir -p "$HYPERPASS_STORAGE"

export HYPERPASS_STORAGE
export HYPERPASS_DISTRIBUTIONS_URL

echo "==> Dev hyperpassd"
echo "    binary:      ${DAEMON}"
echo "    socket:      unix:${HYPERPASS_SOCKET}"
echo "    storage:     ${HYPERPASS_STORAGE}"
echo "    catalog:     ${HYPERPASS_DISTRIBUTIONS_URL}"
echo
echo "    CLI/GUI:     export HYPERPASS_SERVER_ADDRESS=unix:${HYPERPASS_SOCKET}"
echo "                 export PATH=\"${BUILD_DIR}/bin:\$PATH\""
echo "                 ./scripts/run-dev-gui.sh"
echo
echo "    Stop:        Ctrl-C, or: $(basename "$0") --stop"
echo

if [[ $EUID -eq 0 ]]; then
  exec "$DAEMON" \
    --logger stderr \
    --verbosity "$VERBOSITY" \
    --address "unix:${HYPERPASS_SOCKET}" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
else
  exec sudo -E "$DAEMON" \
    --logger stderr \
    --verbosity "$VERBOSITY" \
    --address "unix:${HYPERPASS_SOCKET}" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
fi
