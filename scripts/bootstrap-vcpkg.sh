#!/usr/bin/env bash
# Bootstrap the vcpkg tool binary with a visible download progress bar.
# Skips re-download when an existing binary matches the expected SHA-512.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VCPKG_ROOT="${VCPKG_ROOT:-${ROOT}/3rd-party/vcpkg}"
VCPKG_BIN="${VCPKG_ROOT}/vcpkg"
METADATA="${VCPKG_ROOT}/scripts/vcpkg-tool-metadata.txt"

metadata_value() {
  local key="$1"
  grep "^${key}=" "${METADATA}" | cut -d= -f2- | tr -d '\r'
}

sha512_file() {
  if command -v sha512sum >/dev/null 2>&1; then
    sha512sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 512 "$1" | awk '{print $1}'
  else
    echo "error: sha512sum or shasum is required to verify vcpkg downloads" >&2
    exit 1
  fi
}

select_vcpkg_tool() {
  local uname arch
  uname="$(uname)"
  arch="$(uname -m)"

  if [[ "${uname}" == "Darwin" ]]; then
    TOOL_NAME="vcpkg-macos"
    EXPECTED_SHA="$(metadata_value VCPKG_MACOS_SHA)"
    return 0
  fi

  if [[ "${uname}" != "Linux" ]]; then
    return 1
  fi

  local use_musl="OFF"
  if [[ -f /etc/alpine-release ]]; then
    use_musl="ON"
  fi

  if [[ "${use_musl}" == "ON" && "${arch}" == "x86_64" ]]; then
    TOOL_NAME="vcpkg-muslc"
    EXPECTED_SHA="$(metadata_value VCPKG_MUSLC_SHA)"
    return 0
  fi

  if [[ "${arch}" == "x86_64" ]]; then
    TOOL_NAME="vcpkg-glibc"
    EXPECTED_SHA="$(metadata_value VCPKG_GLIBC_SHA)"
    return 0
  fi

  if [[ "${arch}" == "aarch64" || "${arch}" == "arm64" ]]; then
    TOOL_NAME="vcpkg-glibc-arm64"
    EXPECTED_SHA="$(metadata_value VCPKG_GLIBC_ARM64_SHA)"
    return 0
  fi

  return 1
}

if [[ ! -f "${METADATA}" ]]; then
  echo "error: vcpkg submodule metadata not found at ${METADATA}" >&2
  echo "       Run: git submodule update --init --recursive" >&2
  exit 1
fi

if ! select_vcpkg_tool; then
  echo "==> Unsupported host for prebuilt vcpkg; using upstream bootstrap..."
  exec "${VCPKG_ROOT}/bootstrap-vcpkg.sh" "$@"
fi

VCPKG_TOOL_RELEASE_TAG="$(metadata_value VCPKG_TOOL_RELEASE_TAG)"
URL="https://github.com/microsoft/vcpkg-tool/releases/download/${VCPKG_TOOL_RELEASE_TAG}/${TOOL_NAME}"

if [[ -x "${VCPKG_BIN}" ]]; then
  actual_sha="$(sha512_file "${VCPKG_BIN}")"
  if [[ "${actual_sha}" == "${EXPECTED_SHA}" ]]; then
    echo "==> vcpkg already bootstrapped (${TOOL_NAME})"
    exit 0
  fi
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required to download vcpkg" >&2
  exit 1
fi

PART="${VCPKG_BIN}.part"
rm -f "${PART}"

echo "==> Downloading ${TOOL_NAME} from GitHub..."
if [[ -t 1 ]]; then
  curl -L "${URL}" --tlsv1.2 --retry 3 --fail --output "${PART}" --progress-bar
else
  curl -L "${URL}" --tlsv1.2 --retry 3 --fail --output "${PART}" --silent --show-error
fi

actual_sha="$(sha512_file "${PART}")"
if [[ "${actual_sha}" != "${EXPECTED_SHA}" ]]; then
  echo "error: downloaded ${TOOL_NAME} has unexpected SHA-512" >&2
  echo "       expected: ${EXPECTED_SHA}" >&2
  echo "       actual:   ${actual_sha}" >&2
  rm -f "${PART}"
  exit 1
fi

chmod +x "${PART}"
mv "${PART}" "${VCPKG_BIN}"
"${VCPKG_BIN}" version --disable-metrics
echo "==> vcpkg bootstrap complete"
