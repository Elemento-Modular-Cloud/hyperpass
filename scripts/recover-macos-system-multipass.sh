#!/usr/bin/env bash
# Restore the stock macOS Multipass CLI after a local multipassd overwrote the
# shared root CA at /usr/local/etc/multipassd/multipass_root_cert.pem.
#
# Symptom:
#   WARNING: All log messages before absl::InitializeLog() ...
#   Handshake failed ... certificate verify failed
#   multipass   1.x.y+mac          # client only; daemon line missing
#   list failed: cannot connect to the multipass socket
#
# Requires sudo. Quits Multipass GUI helpers so they pick up the new CA.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="/Library/LaunchDaemons/com.canonical.multipassd.plist"
ROOT_CERT="/usr/local/etc/multipassd/multipass_root_cert.pem"
DAEMON_CERT_DIR="/var/root/Library/Application Support/multipassd/certificates"
ELP_SOCKET="${ELP_SOCKET:-/tmp/elp.socket}"
LOCAL_DAEMON="${ROOT}/build/bin/elpd"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--yes]

Stops any local elpd, regenerates the system Multipass daemon's gRPC
certificates (and shared root CA), reloads com.canonical.multipassd, and
checks \`multipass version\`.

Options:
  --yes, -y   Skip the confirmation prompt
  -h, --help  Show this help

Environment:
  ELP_SOCKET   Local unix socket to remove (default: ${ELP_SOCKET})
EOF
}

confirm=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) confirm=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script only supports macOS." >&2
  exit 1
fi

if [[ ! -f "$PLIST" ]]; then
  echo "System Multipass LaunchDaemon not found at $PLIST" >&2
  exit 1
fi

if [[ $confirm -eq 1 ]]; then
  cat <<EOF
This will:
  1. Stop local elpd (${LOCAL_DAEMON} / ${ELP_SOCKET})
  2. Unload ${PLIST}
  3. Delete gRPC certs under ${DAEMON_CERT_DIR}
  4. Delete shared root CA ${ROOT_CERT}
  5. Reload the system daemon and verify \`multipass version\`

Running VMs may briefly restart with the daemon.
EOF
  read -r -p "Continue? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

echo "==> Stopping local elpd (if any)"
if [[ -x "$LOCAL_DAEMON" ]]; then
  sudo pkill -f "$LOCAL_DAEMON" 2>/dev/null || true
fi
sudo pkill -f "unix:${ELP_SOCKET#unix:}" 2>/dev/null || true
sudo pkill -f "unix:${ELP_SOCKET}" 2>/dev/null || true
if [[ -e "$ELP_SOCKET" ]]; then
  sudo rm -f "$ELP_SOCKET"
fi

echo "==> Quitting Multipass GUI (so it reloads credentials)"
osascript -e 'quit app "Multipass"' 2>/dev/null || true
sudo killall Multipass 2>/dev/null || true

echo "==> Unloading system multipassd"
sudo launchctl unload "$PLIST" 2>/dev/null || true
# Ensure the daemon is gone before rewriting certs.
sudo pkill -x multipassd 2>/dev/null || true
sleep 1

echo "==> Removing stale gRPC / root certificates"
sudo rm -f \
  "${DAEMON_CERT_DIR}/localhost.pem" \
  "${DAEMON_CERT_DIR}/localhost_key.pem" \
  "${DAEMON_CERT_DIR}/localhost_root_key.pem" \
  "$ROOT_CERT"

echo "==> Reloading system multipassd"
sudo launchctl load "$PLIST"
sleep 2

echo "==> Checking multipass version"
# \`multipass version\` often exits 0 even when the daemon handshake fails.
out="$(multipass version 2>&1 || true)"
echo "$out"

if echo "$out" | grep -Eq 'certificate verify failed|cannot connect to the multipass socket'; then
  echo "Still seeing TLS/socket errors; inspect /Library/Logs/Multipass/multipassd.log" >&2
  exit 1
fi

if ! echo "$out" | grep -q 'multipassd'; then
  echo "Expected a multipassd version line; recovery may be incomplete." >&2
  echo "Inspect /Library/Logs/Multipass/multipassd.log" >&2
  exit 1
fi

echo "System Multipass CLI should be usable again. Re-open the Multipass GUI if needed."
echo
echo "When testing a custom daemon next time, keep ELP_STORAGE and --address"
echo "separate (see LOCAL_DEV.md). Note: on macOS the root CA path is still shared;"
echo "run this script again after local multipassd sessions that regenerate certs."
