#!/usr/bin/env bash
# Build Multipass on Linux (see BUILD.linux.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
BUILD_TYPE="${BUILD_TYPE:-Debug}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
DO_SUBMODULES=1
DO_CONFIGURE=1
DO_BUILD=1
DO_TEST=0
DO_PACKAGE=0
GTEST_FILTER=""
EXTRA_CMAKE_ARGS=()
GENERATOR=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- <extra cmake configure args>]

Options:
  --build-dir DIR     Build directory (default: ${ROOT}/build)
  --build-type TYPE   CMake build type (default: Debug)
  --jobs N            Parallel build jobs (default: ${JOBS})
  --ninja             Force the Ninja generator
  --no-submodules     Skip git submodule update
  --configure-only    Only run CMake configure
  --build-only        Skip configure; build existing tree
  --test              Run ctest after build
  --gtest-filter F    Pass --gtest_filter to multipass_cpp_tests (implies --test)
  --package           Build the package target after build
  -h, --help          Show this help

Environment:
  BUILD_DIR, BUILD_TYPE, JOBS, CMAKE_ARGS
  VCPKG_FORCE_SYSTEM_BINARIES is set automatically on non-x86_64 hosts.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir) BUILD_DIR="$2"; shift 2 ;;
    --build-type) BUILD_TYPE="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --ninja) GENERATOR=(-GNinja); shift ;;
    --no-submodules) DO_SUBMODULES=0; shift ;;
    --configure-only) DO_BUILD=0; DO_TEST=0; DO_PACKAGE=0; shift ;;
    --build-only) DO_CONFIGURE=0; shift ;;
    --test) DO_TEST=1; shift ;;
    --gtest-filter) GTEST_FILTER="$2"; DO_TEST=1; shift 2 ;;
    --package) DO_PACKAGE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA_CMAKE_ARGS+=("$@"); break ;;
    *) EXTRA_CMAKE_ARGS+=("$1"); shift ;;
  esac
done

if [[ -n "${CMAKE_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_CMAKE_ARGS+=(${CMAKE_ARGS})
fi

cd "${ROOT}"

arch="$(uname -m)"
case "${arch}" in
  x86_64|amd64) ;;
  *)
    export VCPKG_FORCE_SYSTEM_BINARIES=1
    echo "==> Non-x86_64 host (${arch}): VCPKG_FORCE_SYSTEM_BINARIES=1"
    ;;
esac

if command -v ninja >/dev/null 2>&1 && [[ ${#GENERATOR[@]} -eq 0 ]]; then
  GENERATOR=(-GNinja)
fi

if [[ "${DO_SUBMODULES}" -eq 1 ]]; then
  echo "==> Updating submodules"
  git submodule update --init --recursive
fi

mkdir -p "${BUILD_DIR}"

if [[ "${DO_CONFIGURE}" -eq 1 ]]; then
  echo "==> Configuring (${BUILD_TYPE}) in ${BUILD_DIR}"
  # Bash 3.2 treats empty "${arr[@]}" as unbound under set -u.
  cmake -S "${ROOT}" -B "${BUILD_DIR}" \
    ${GENERATOR[@]+"${GENERATOR[@]}"} \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    ${EXTRA_CMAKE_ARGS[@]+"${EXTRA_CMAKE_ARGS[@]}"}
fi

if [[ "${DO_BUILD}" -eq 1 ]]; then
  echo "==> Building (jobs=${JOBS})"
  cmake --build "${BUILD_DIR}" --parallel "${JOBS}"
fi

if [[ "${DO_TEST}" -eq 1 ]]; then
  echo "==> Running tests"
  if [[ -n "${GTEST_FILTER}" ]]; then
    "${BUILD_DIR}/bin/multipass_cpp_tests" --gtest_filter="${GTEST_FILTER}"
  else
    ctest --test-dir "${BUILD_DIR}" --output-on-failure
  fi
fi

if [[ "${DO_PACKAGE}" -eq 1 ]]; then
  echo "==> Packaging"
  cmake --build "${BUILD_DIR}" --target package --parallel "${JOBS}"
fi

echo "==> Done"
