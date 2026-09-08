#!/usr/bin/env bash
# Ensure a clone-shaped elemento-marketplace checkout exists for the GUI.
#
# The app reads `ELP_MARKETPLACE_DIR` (repo root or its `services/` folder)
# and reloads when those files change. Production will drop the same layout
# via CDN; for local testing this clones GitHub.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="${ELP_MARKETPLACE_REPO:-https://github.com/Elemento-Modular-Cloud/elemento-marketplace.git}"
REF="${ELP_MARKETPLACE_REF:-feat-cloudinit-imp}"
DEST="${ELP_MARKETPLACE_DIR:-${ROOT}/.cache/elemento-marketplace}"

if [[ -d "${DEST}/services" && -d "${DEST}/.git" ]]; then
  # Fast-forward when online so icon / color metadata stays current.
  if git -C "${DEST}" fetch --quiet origin "${REF}" 2>/dev/null; then
    git -C "${DEST}" merge --ff-only --quiet "origin/${REF}" 2>/dev/null || true
  fi
  printf '%s\n' "${DEST}"
  exit 0
fi

if [[ -d "${DEST}/services" ]]; then
  # Unsigned drop (CDN / unpacked tree) — good enough.
  printf '%s\n' "${DEST}"
  exit 0
fi

mkdir -p "$(dirname "${DEST}")"
echo "==> Cloning marketplace ${REF} into ${DEST}" >&2
git clone --branch "${REF}" --single-branch "${REPO_URL}" "${DEST}"
printf '%s\n' "${DEST}"
