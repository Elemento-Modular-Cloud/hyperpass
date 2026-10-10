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
  BUILD_DIR, BUILD_TYPE, JOBS, CMAKE_ARGS, CMAKE
  VCPKG_FORCE_SYSTEM_BINARIES is set automatically on non-x86_64 hosts.
  CMAKE, if set, must be CMake >= 3.29 (Ubuntu 24.04 apt is 3.28.x).
EOF
}

# Hyperpass requires CMake >= 3.29. Ubuntu 24.04 apt still ships 3.28.x; prefer
# snap cmake (/snap/bin) or an explicit CMAKE= override when PATH would pick apt.
MIN_CMAKE_VERSION="3.29"

cmake_version() {
  local bin="$1"
  "${bin}" --version 2>/dev/null | awk 'NR==1 {print $3; exit}'
}

version_ge() {
  # True if $1 >= $2 (dotted numeric versions).
  printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1 | grep -qx "$2"
}

resolve_cmake() {
  local candidates=()
  if [[ -n "${CMAKE:-}" ]]; then
    candidates+=("${CMAKE}")
  fi
  if command -v cmake >/dev/null 2>&1; then
    candidates+=("$(command -v cmake)")
  fi
  # Snap classic cmake is the documented Ubuntu 24.04 workaround (BUILD.linux.md).
  if [[ -x /snap/bin/cmake ]]; then
    candidates+=("/snap/bin/cmake")
  fi

  local seen=""
  local cand ver
  for cand in "${candidates[@]}"; do
    [[ -n "${cand}" && -x "${cand}" ]] || continue
    case " ${seen} " in
      *" ${cand} "*) continue ;;
    esac
    seen+=" ${cand}"
    ver="$(cmake_version "${cand}")"
    if [[ -n "${ver}" ]] && version_ge "${ver}" "${MIN_CMAKE_VERSION}"; then
      echo "${cand}"
      return 0
    fi
  done
  return 1
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

if ! CMAKE_BIN="$(resolve_cmake)"; then
  echo "error: CMake >= ${MIN_CMAKE_VERSION} is required (see BUILD.linux.md)." >&2
  if command -v cmake >/dev/null 2>&1; then
    echo "       Found $(command -v cmake) ($(cmake_version "$(command -v cmake)"))." >&2
  fi
  echo "       On Ubuntu 24.04:" >&2
  echo "         sudo snap install cmake --classic" >&2
  echo "         # or: CMAKE=/snap/bin/cmake ./scripts/build-linux.sh" >&2
  exit 1
fi
echo "==> Using CMake ${CMAKE_BIN} ($(cmake_version "${CMAKE_BIN}"))"

if command -v ninja >/dev/null 2>&1 && [[ ${#GENERATOR[@]} -eq 0 ]]; then
  GENERATOR=(-GNinja)
fi

if [[ "${DO_SUBMODULES}" -eq 1 ]]; then
  echo "==> Updating submodules"
  git submodule update --init --recursive
fi

mkdir -p "${BUILD_DIR}"

if [[ "${DO_CONFIGURE}" -eq 1 ]]; then
  "${ROOT}/scripts/bootstrap-vcpkg.sh"
  echo "==> Configuring (${BUILD_TYPE}) in ${BUILD_DIR}"
  # Bash 3.2 treats empty "${arr[@]}" as unbound under set -u.
  "${CMAKE_BIN}" -S "${ROOT}" -B "${BUILD_DIR}" \
    ${GENERATOR[@]+"${GENERATOR[@]}"} \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    ${EXTRA_CMAKE_ARGS[@]+"${EXTRA_CMAKE_ARGS[@]}"}
fi

if [[ "${DO_BUILD}" -eq 1 ]]; then
  echo "==> Building (jobs=${JOBS})"
  "${CMAKE_BIN}" --build "${BUILD_DIR}" --parallel "${JOBS}"
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
  "${CMAKE_BIN}" --build "${BUILD_DIR}" --target package --parallel "${JOBS}"
fi

echo "==> Done"
