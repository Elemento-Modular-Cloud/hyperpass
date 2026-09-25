#!/usr/bin/env bash
# Alias: build-tree elpd already defaults to the Spacedock image catalog.
# Pair with ./scripts/run-spacedock-gui.sh and sign in.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unset ELP_DISTRIBUTIONS_URL
exec "${ROOT}/scripts/run-dev-daemon.sh" "$@"
