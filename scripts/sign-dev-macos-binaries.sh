#!/usr/bin/env bash
# Ad-hoc sign dev-tree binaries that need macOS entitlements (see LOCAL_DEV.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
BIN_DIR="${BUILD_DIR}/bin"
SIGN_ID="${SIGN_ID:--}"
QEMU_ENT="${ROOT}/packaging/macos/dev-qemu.entitlements.plist"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Apply ad-hoc codesign entitlements needed for local QEMU/HVF development.
Packaged builds use packaging/macos/sign-and-notarize.sh instead.

Options:
  --build-dir DIR   Build directory (default: ${BUILD_DIR})
  --sign-id ID      codesign identity (default: adhoc "-")
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir) BUILD_DIR="$2"; BIN_DIR="${BUILD_DIR}/bin"; shift 2 ;;
    --sign-id) SIGN_ID="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != Darwin ]]; then
  echo "==> Skipping (not macOS)"
  exit 0
fi

if [[ ! -d "${BIN_DIR}" ]]; then
  echo "error: ${BIN_DIR} not found; build first" >&2
  exit 1
fi

if ! command -v codesign >/dev/null 2>&1; then
  echo "error: codesign not found (install Xcode command line tools)" >&2
  exit 1
fi

signed=0
shopt -s nullglob
for qemu in "${BIN_DIR}"/qemu-system-*; do
  [[ -f "${qemu}" ]] || continue
  echo "==> Signing $(basename "${qemu}")"
  codesign --force --sign "${SIGN_ID}" --entitlements "${QEMU_ENT}" "${qemu}"
  signed=1
done

if [[ "${signed}" -eq 0 ]]; then
  echo "warning: no qemu-system-* binary found under ${BIN_DIR}" >&2
  exit 1
fi

echo "==> Done"
