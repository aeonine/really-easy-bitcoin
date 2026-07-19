#!/usr/bin/env bash
set -euo pipefail

# Show status for the Bitcoin Core node tied to this folder.
# Resolve from the script location so info reports the portable bundle it lives
# in, regardless of where the user runs it from.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BITCOIN_CLI="${BASE_DIR}/bitcoin-cli"
DATA_DIR="${BASE_DIR}/bitcoin-data"
PID_FILE="${BASE_DIR}/bitcoind.pid"
TOR_PID_FILE="${BASE_DIR}/tor.pid"
INFO_WAIT_SECONDS="${INFO_WAIT_SECONDS:-15}"
INFO_JSON="$(mktemp)"
INFO_ERR="$(mktemp)"

cleanup() {
  # Remove temporary RPC output files even when bitcoin-cli fails.
  rm -f "$INFO_JSON" "$INFO_ERR"
}
trap cleanup EXIT

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

section() {
  printf '\n== %s ==\n' "$1"
}

cli() {
  # Always point bitcoin-cli at the folder-local datadir and auth cookie.
  "$BITCOIN_CLI" -datadir="$DATA_DIR" "$@"
}

[ -x "$BITCOIN_CLI" ] || die "missing executable: $BITCOIN_CLI; run ./install.sh first"

printf 'Folder: %s\n' "$BASE_DIR"
printf 'Data:   %s\n' "$DATA_DIR"

# PID files are advisory: confirm the process still exists before reporting it
# as running.
if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE")"
  if [ -n "$PID" ] && kill -0 "$PID" >/dev/null 2>&1; then
    printf 'PID:    %s\n' "$PID"
  else
    printf 'PID:    stale pid file\n'
  fi
else
  printf 'PID:    none\n'
fi

# Report the bundled Tor daemon separately from Bitcoin Core.
if [ -f "$TOR_PID_FILE" ]; then
  TOR_PID="$(cat "$TOR_PID_FILE")"
  if [ -n "$TOR_PID" ] && kill -0 "$TOR_PID" >/dev/null 2>&1; then
    printf 'Tor:    running with PID %s\n' "$TOR_PID"
  else
    printf 'Tor:    stale pid file\n'
  fi
else
  printf 'Tor:    none\n'
fi

# getblockchaininfo is the reachability probe. Store stdout/stderr separately so
# success output can be reused below and failures show the RPC error cleanly.
# Bitcoin Core returns RPC code -28 while it is warming up; retry that briefly.
for _ in $(seq 1 "$INFO_WAIT_SECONDS"); do
  : > "$INFO_JSON"
  : > "$INFO_ERR"
  if cli getblockchaininfo >"$INFO_JSON" 2>"$INFO_ERR"; then
    printf 'Status: reachable\n'
    break
  fi

  if grep -q 'error code: -28' "$INFO_ERR"; then
    printf 'Status: starting\n'
    sleep 1
    continue
  fi

  printf 'Status: not reachable\n'
  if [ -s "$INFO_ERR" ]; then
    printf '\n'
    cat "$INFO_ERR" >&2
  fi
  exit 1
done

if [ ! -s "$INFO_JSON" ]; then
  printf 'Status: still starting after %s seconds\n' "$INFO_WAIT_SECONDS"
  if [ -s "$INFO_ERR" ]; then
    printf '\n'
    cat "$INFO_ERR" >&2
  fi
  exit 1
fi

# These RPC calls are read-only status views.
section "Blockchain"
cat "$INFO_JSON"

section "Network"
cli getnetworkinfo

section "Wallets"
cli listwallets
