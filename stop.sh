#!/usr/bin/env bash
set -euo pipefail

# Stop the Bitcoin Core node that uses this folder's local data directory.
# Resolve paths from the script location so stop works from any shell directory.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BITCOIN_CLI="${BASE_DIR}/bitcoin-cli"
DATA_DIR="${BASE_DIR}/bitcoin-data"
PID_FILE="${BASE_DIR}/bitcoind.pid"
STOP_TOR="${BASE_DIR}/stop-tor.sh"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

stop_bitcoin() {
  # Normal path: use the current bitcoin.conf/default RPC settings.
  if "$BITCOIN_CLI" -datadir="$DATA_DIR" stop; then
    return 0
  fi

  # Migration fallback for bundles started while the temporary rpcport=28332
  # setting existed. Once that old process is stopped, future starts use 8332.
  "$BITCOIN_CLI" -datadir="$DATA_DIR" -rpcport=28332 stop
}

[ -x "$BITCOIN_CLI" ] || die "missing executable: $BITCOIN_CLI; run ./install.sh first"
[ -d "$DATA_DIR" ] || die "missing data directory: $DATA_DIR; run ./start.sh first"

# Keep track of partial failures so we can still try to stop Tor after a Bitcoin
# RPC failure, then return a non-zero status at the end.
STOP_EXIT=0

printf 'Stopping Bitcoin Core\n'
# Use Bitcoin Core's RPC stop command through the local datadir cookie.
if stop_bitcoin; then
  rm -f "$PID_FILE"
  printf 'Stop requested.\n'
else
  printf 'warning: could not contact Bitcoin Core; it may already be stopped\n' >&2
  STOP_EXIT=1
fi

# Tor is a separate daemon. Stop it after the Bitcoin stop request so the node
# can make its final RPC/network calls while the proxy still exists.
if [ -x "$STOP_TOR" ]; then
  "$STOP_TOR" || STOP_EXIT=1
fi

exit "$STOP_EXIT"
