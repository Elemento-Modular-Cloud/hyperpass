#!/usr/bin/env bash
# Start build-tree elpd with the live Spacedock image catalog (not the local
# distribution-info.json). Pair with ./scripts/run-spacedock-gui.sh and sign in.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ELP_SPACEDOCK=1
unset ELP_DISTRIBUTIONS_URL
exec "${ROOT}/scripts/run-dev-daemon.sh" "$@"
