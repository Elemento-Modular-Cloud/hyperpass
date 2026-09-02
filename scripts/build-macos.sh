#!/usr/bin/env bash
# Build Multipass on macOS (see BUILD.macOS.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
BUILD_TYPE="${BUILD_TYPE:-Debug}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
DO_SUBMODULES=1
DO_CONFIGURE=1
DO_BUILD=1
DO_TEST=0
DO_PACKAGE=0
GTEST_FILTER=""
EXTRA_CMAKE_ARGS=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- <extra cmake configure args>]

Options:
  --build-dir DIR     Build directory (default: ${ROOT}/build)
  --build-type TYPE   CMake build type (default: Debug)
  --jobs N            Parallel build jobs (default: ${JOBS})
  --no-submodules     Skip git submodule update
  --configure-only    Only run CMake configure
  --build-only        Skip configure; build existing tree
  --test              Run ctest after build
  --gtest-filter F    Pass --gtest_filter to multipass_cpp_tests (implies --test)
  --package           Build the package target after build
  -h, --help          Show this help

Environment:
  BUILD_DIR, BUILD_TYPE, JOBS, CMAKE_ARGS
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir) BUILD_DIR="$2"; shift 2 ;;
    --build-type) BUILD_TYPE="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
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

# Homebrew libtool installs libtoolize as glibtoolize; vcpkg expects libtoolize.
if [[ -d /usr/local/opt/libtool/libexec/gnubin ]]; then
  export PATH="/usr/local/opt/libtool/libexec/gnubin:${PATH}"
elif [[ -d /opt/homebrew/opt/libtool/libexec/gnubin ]]; then
  export PATH="/opt/homebrew/opt/libtool/libexec/gnubin:${PATH}"
fi

# Prefer native arm64 Homebrew tools when available (avoids Rosetta/Qt cross issues).
if [[ -x /opt/homebrew/bin/cmake ]]; then
  export PATH="/opt/homebrew/bin:${PATH}"
fi

# Rust crates (rxx/namegen) must match the C++ link arch. Intel Homebrew rustc under
# /usr/local produces x86_64 libnamegen.a that arm64 ld then drops → undefined cxxbridge
# symbols. Prefer /opt/homebrew cargo/rustc on Apple Silicon.
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]]; then
  if [[ -x /opt/homebrew/bin/cargo && -x /opt/homebrew/bin/rustc ]]; then
    export PATH="/opt/homebrew/bin:${PATH}"
  fi
  rustc_bin="$(command -v rustc || true)"
  rustc_arch="$(file -b "${rustc_bin}" 2>/dev/null || true)"
  if [[ -n "${rustc_bin}" && "${rustc_arch}" == *x86_64* && "${rustc_arch}" != *arm64* ]]; then
    echo "error: rustc is x86_64 (${rustc_bin}) but this Mac builds arm64 C++." >&2
    echo "       Install native Rust and put it first on PATH, e.g.:" >&2
    echo "         brew install rust" >&2
    echo "         # ensure /opt/homebrew/bin precedes /usr/local/bin" >&2
    echo "       Then wipe the stale Rust artifacts and rebuild:" >&2
    echo "         rm -rf build/rxx" >&2
    echo "         # if CMake cached Intel cargo: delete CARGO_EXECUTABLE from build/CMakeCache.txt" >&2
    exit 1
  fi
fi

if ! command -v ninja >/dev/null 2>&1; then
  echo "error: ninja not found; install with: brew install ninja" >&2
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake not found; install with: brew install cmake" >&2
  exit 1
fi

# AppleClang injects -I/usr/local/include ahead of vcpkg -isystem paths, so
# Homebrew abseil headers shadow vcpkg and break the protobuf link (LTS mismatch).
if [[ -e /usr/local/include/absl/base/options.h ]] || [[ -e /opt/homebrew/include/absl/base/options.h ]]; then
  echo "error: Homebrew Abseil headers shadow vcpkg includes." >&2
  echo "       Uninstall or unlink them, then clean and reconfigure:" >&2
  echo "         brew uninstall --ignore-dependencies abseil" >&2
  echo "         rm -rf build 3rd-party/vcpkg/buildtrees/{abseil,protobuf}" >&2
  exit 1
fi

for tool in autoconf automake libtoolize; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: ${tool} not found; install with:" >&2
    echo "         brew install autoconf autoconf-archive automake libtool" >&2
    exit 1
  fi
done

python3_bin="$(command -v python3 || true)"
if [[ -z "${python3_bin}" ]]; then
  echo "error: python3 not found" >&2
  exit 1
fi
if ! "${python3_bin}" -c "import distlib" 2>/dev/null; then
  echo "error: Python distlib is required to configure QEMU (found ${python3_bin})." >&2
  echo "       Install with:" >&2
  echo "         ${python3_bin} -m pip install distlib --break-system-packages" >&2
  exit 1
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "error: CocoaPods not found (required for the Flutter macOS GUI)." >&2
  echo "       Install with: brew install cocoapods" >&2
  exit 1
fi

cmake_arch="$(file -b "$(command -v cmake)" 2>/dev/null || true)"
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]] && [[ "${cmake_arch}" == *x86_64* && "${cmake_arch}" != *arm64* ]]; then
  echo "warning: cmake is x86_64 on Apple Silicon (Rosetta). Building x64-osx." >&2
  echo "         For native arm64, install Homebrew in /opt/homebrew and its cmake." >&2
fi

if [[ "${DO_SUBMODULES}" -eq 1 ]]; then
  echo "==> Updating submodules"
  git submodule update --init --recursive
fi

mkdir -p "${BUILD_DIR}"

if [[ "${DO_CONFIGURE}" -eq 1 ]]; then
  "${ROOT}/scripts/bootstrap-vcpkg.sh"
  echo "==> Configuring (${BUILD_TYPE}) in ${BUILD_DIR}"
  # Bash 3.2 (macOS) treats empty "${arr[@]}" as unbound under set -u.
  cmake -S "${ROOT}" -B "${BUILD_DIR}" \
    -GNinja \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    ${EXTRA_CMAKE_ARGS[@]+"${EXTRA_CMAKE_ARGS[@]}"}
fi

if [[ "${DO_BUILD}" -eq 1 ]]; then
  echo "==> Building (jobs=${JOBS})"
  cmake --build "${BUILD_DIR}" --parallel "${JOBS}"
  echo "==> Signing dev QEMU binaries (HVF entitlements)"
  "${ROOT}/scripts/sign-dev-macos-binaries.sh" --build-dir "${BUILD_DIR}"
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
