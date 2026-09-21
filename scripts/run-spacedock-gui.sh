#!/usr/bin/env bash
# Launch the build-tree GUI against Spacedock's marketplace bundle (not a local
# elemento-marketplace checkout). Pair with ./scripts/run-spacedock-daemon.sh
# and sign in so the Portal JWT is sent to the gate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ELP_SPACEDOCK=1
unset ELP_MARKETPLACE_DIR
unset ELP_MARKETPLACE_URL
exec "${ROOT}/scripts/run-dev-gui.sh" "$@"
