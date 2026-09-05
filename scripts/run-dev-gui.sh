#!/usr/bin/env bash
# Launch the built Electros LaunchPad GUI against the dev elpd (see LOCAL_DEV.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
ELP_SOCKET="${ELP_SOCKET:-/tmp/elp.socket}"
GUI_APP=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- <extra app args>]

Launch the built Electros LaunchPad GUI pointed at the dev daemon socket. Run
./scripts/run-dev-daemon.sh in another terminal first.

Options:
  --build-dir DIR   Build directory (default: ${BUILD_DIR})
  -h, --help        Show this help

Environment:
  BUILD_DIR                 Build tree (default: ${ROOT}/build)
  ELP_SOCKET          Dev daemon socket (default: ${ELP_SOCKET})
  ELP_SERVER_ADDRESS  Overrides the socket if set
EOF
}

resolve_gui_app() {
  local bin_dir="${BUILD_DIR}/bin"
  local candidates=()

  case "$(uname -s)" in
    Darwin)
      candidates=(
        "${bin_dir}/Electros LaunchPad.app/Contents/MacOS/Electros LaunchPad"
        "${bin_dir}/macos/Build/Products/Release/Electros LaunchPad.app/Contents/MacOS/Electros LaunchPad"
      )
      ;;
    Linux)
      local arch
      case "$(uname -m)" in
        x86_64|amd64) arch=x64 ;;
        aarch64|arm64) arch=arm64 ;;
        *)
          echo "error: unsupported Linux architecture: $(uname -m)" >&2
          exit 1
          ;;
      esac
      candidates=(
        "${bin_dir}/linux/${arch}/release/bundle/elp_gui"
        "${bin_dir}/elp.gui"
      )
      ;;
    *)
      echo "error: unsupported platform: $(uname -s)" >&2
      exit 1
      ;;
  esac

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      GUI_APP="$candidate"
      return
    fi
  done

  GUI_APP="${candidates[0]}"
}

EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir) BUILD_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

resolve_gui_app

if [[ ! -x "$GUI_APP" ]]; then
  echo "error: GUI not found at ${GUI_APP}" >&2
  echo "       Build first (Flutter GUI enabled): ./scripts/build-macos.sh" >&2
  exit 1
fi

export ELP_SERVER_ADDRESS="${ELP_SERVER_ADDRESS:-unix:${ELP_SOCKET}}"
export PATH="${BUILD_DIR}/bin:${PATH}"

if [[ ! -S "$ELP_SOCKET" ]]; then
  echo "warning: dev daemon socket not found at ${ELP_SOCKET}" >&2
  echo "         Start the daemon: ./scripts/run-dev-daemon.sh" >&2
fi

echo "==> Dev Electros LaunchPad GUI"
echo "    binary:  ${GUI_APP}"
echo "    daemon:  ${ELP_SERVER_ADDRESS}"
echo

exec "$GUI_APP" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
