#!/usr/bin/env bash
set -euo pipefail

# Refresh the portable Bitcoin Core, Tor, and Sparrow runtimes while preserving
# local data folders such as bitcoin-data/, tor-data/, and sparrow-home/.
# Resolve paths from the script location so updates target this portable bundle.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="${BASE_DIR}/install.sh"
STOP_BITCOIN="${BASE_DIR}/stop.sh"
STOP_TOR="${BASE_DIR}/stop-tor.sh"
BITCOIN_PID_FILE="${BASE_DIR}/bitcoind.pid"
TOR_PID_FILE="${BASE_DIR}/tor.pid"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

pid_is_running() {
  local pid_file="$1"
  local pid

  # PID files can be stale, especially on removable media. Treat the process as
  # running only if kill -0 confirms the PID still exists.
  [ -f "$pid_file" ] || return 1
  pid="$(cat "$pid_file")"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

[ -x "$INSTALLER" ] || die "missing executable installer: $INSTALLER"

printf 'Updating portable bundle in %s\n' "$BASE_DIR"

# Stop running daemons before replacing binaries or runtimes. stop.sh also stops
# Tor after Bitcoin Core, so use the Tor-only path only when Bitcoin is not up.
if pid_is_running "$BITCOIN_PID_FILE"; then
  [ -x "$STOP_BITCOIN" ] || die "Bitcoin Core is running but $STOP_BITCOIN is missing"
  "$STOP_BITCOIN"
elif pid_is_running "$TOR_PID_FILE"; then
  [ -x "$STOP_TOR" ] || die "Tor is running but $STOP_TOR is missing"
  "$STOP_TOR"
fi

(
  # install.sh is path-safe, but running from BASE_DIR keeps component behavior
  # obvious and matches the normal manual invocation.
  cd "$BASE_DIR"
  "$INSTALLER"
)

printf '\nUpdate complete.\n'
