#!/usr/bin/env bash
# Build and package elp (elpd + elp CLI + elp GUI) for Arch Linux.
#
# Renders packaging/archlinux/PKGBUILD.in against this checkout, then builds
# it either in a clean chroot via devtools' extra-x86_64-build (default,
# sandboxed) or with a plain `makepkg` in the current environment.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_TEMPLATE="${ROOT}/packaging/archlinux/PKGBUILD.in"
SERVICE_FILE="${ROOT}/packaging/archlinux/elpd.service"
API_SERVICE_FILE="${ROOT}/packaging/archlinux/elp-api.service"
SCRATCH_DIR="${ARCH_PKG_SCRATCH_DIR:-${ROOT}/build/archlinux-pkg}"
VCPKG_CACHE_DIR="${ARCH_PKG_VCPKG_CACHE:-${ROOT}/build/vcpkg-binary-cache}"
SANDBOXED=1
EXTRA_ARGS=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- <extra makechrootpkg/makepkg args>]

Options:
  --no-sandbox     Build with a plain 'makepkg' instead of the sandboxed
                    'extra-x86_64-build' chroot (requires devtools).
  --scratch-dir D   Where to render the PKGBUILD (default: ${SCRATCH_DIR})
  --vcpkg-cache D   Persistent vcpkg binary cache dir (default: ${VCPKG_CACHE_DIR})
  -h, --help        Show this help

Requires (sandboxed, default): the 'devtools' package (extra-x86_64-build).
Requires (--no-sandbox): 'base-devel' and every dependency listed in
packaging/archlinux/PKGBUILD.in installed on the host.

vcpkg builds Qt6, gRPC, Boost, and QEMU from source the first time it needs
them. Because 'extra-x86_64-build' rebuilds from a clean chroot copy every
run, that cache would normally be wiped and everything recompiled on every
single build — this script avoids that by bind-mounting a persistent cache
directory (--vcpkg-cache) into the chroot at the same path and pointing
vcpkg's binary cache at it, so only the very first build compiles those
dependencies; later builds (even in a freshly recreated chroot) reuse the
cached binaries. Delete --vcpkg-cache's directory to force a clean rebuild.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-sandbox) SANDBOXED=0; shift ;;
    --scratch-dir) SCRATCH_DIR="$2"; shift 2 ;;
    --vcpkg-cache) VCPKG_CACHE_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

branch="$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD)"
repo_source="file://${ROOT}#branch=${branch}"

mkdir -p "${SCRATCH_DIR}" "${VCPKG_CACHE_DIR}"
# Plain bash substitution (not sed): repo_source contains '#' (the git
# ref fragment), which breaks a '#'-delimited sed s### expression.
rendered="$(cat "${PKG_TEMPLATE}")"
rendered="${rendered//@REPO_SOURCE@/${repo_source}}"
rendered="${rendered//@VCPKG_CACHE_DIR@/${VCPKG_CACHE_DIR}}"
printf '%s\n' "${rendered}" > "${SCRATCH_DIR}/PKGBUILD"
cp "${SERVICE_FILE}" "${SCRATCH_DIR}/elpd.service"
cp "${API_SERVICE_FILE}" "${SCRATCH_DIR}/elp-api.service"

echo "==> Rendered PKGBUILD in ${SCRATCH_DIR} (source: ${repo_source})"
echo "==> vcpkg binary cache: ${VCPKG_CACHE_DIR}"
cd "${SCRATCH_DIR}"

if [[ "${SANDBOXED}" -eq 1 ]]; then
  command -v extra-x86_64-build >/dev/null 2>&1 || {
    echo "error: extra-x86_64-build not found; install 'devtools' or pass --no-sandbox" >&2
    exit 1
  }
  echo "==> Building in a sandboxed extra-x86_64 chroot"
  extra-x86_64-build -- -d "${VCPKG_CACHE_DIR}" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
else
  echo "==> Building with plain makepkg (not sandboxed)"
  makepkg -sf --noconfirm ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
fi

echo "==> Done. Package(s):"
ls -1 ./*.pkg.tar.* 2>/dev/null || true
