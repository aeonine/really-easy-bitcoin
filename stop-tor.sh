#!/usr/bin/env bash
set -euo pipefail

# Stop the local Tor daemon started from this folder.
# Resolve from this script's location so the matching local tor.pid is used.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${BASE_DIR}/tor.pid"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[ -f "$PID_FILE" ] || die "missing PID file: $PID_FILE; Tor may already be stopped"

# The PID file is advisory; validate it before sending a signal.
PID="$(cat "$PID_FILE")"
[ -n "$PID" ] || die "empty PID file: $PID_FILE"

if ! kill -0 "$PID" >/dev/null 2>&1; then
  rm -f "$PID_FILE"
  die "Tor process $PID is not running"
fi

printf 'Stopping Tor with PID %s\n' "$PID"
# A normal TERM lets Tor shut down cleanly.
kill "$PID"
rm -f "$PID_FILE"
printf 'Stop requested.\n'
