#!/usr/bin/env bash
set -euo pipefail

# Run a local Tor daemon from the bundled Tor Expert Bundle.
# Resolve paths from the script location so Tor state follows the portable
# folder even if the command is launched from elsewhere.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${BASE_DIR}/tor-runtime"
DATA_DIR="${BASE_DIR}/tor-data"
TORRC="${DATA_DIR}/torrc"
PID_FILE="${BASE_DIR}/tor.pid"
SOCKS_PORT="${TOR_SOCKS_PORT:-9050}"
CONTROL_PORT="${TOR_CONTROL_PORT:-9051}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

find_tor() {
  # Prefer the real runtime daemon. The bundle also contains debug/tor, which is
  # not the executable we want to launch.
  if [ -f "${RUNTIME_DIR}/tor/tor" ]; then
    printf '%s\n' "${RUNTIME_DIR}/tor/tor"
    return
  fi

  # Fallback for future layout changes, while still skipping debug symbols.
  find "$RUNTIME_DIR" -path "${RUNTIME_DIR}/debug" -prune -o -type f -name tor -print -quit
}

[ -d "$RUNTIME_DIR" ] || die "missing Tor runtime: $RUNTIME_DIR; run ./install.sh first"
TOR_BINARY="$(find_tor)"
[ -n "$TOR_BINARY" ] || die "could not find executable tor binary under $RUNTIME_DIR"
chmod 0755 "$TOR_BINARY"

# Keep Tor's cached state, keys, and logs in the portable folder.
mkdir -p "$DATA_DIR"

# Rewrite torrc each start so port overrides are reflected immediately while
# persistent Tor state stays in DATA_DIR.
cat > "$TORRC" <<EOF
DataDirectory ${DATA_DIR}
PidFile ${PID_FILE}
SocksPort 127.0.0.1:${SOCKS_PORT}
ControlPort 127.0.0.1:${CONTROL_PORT}
CookieAuthentication 1
Log notice file ${DATA_DIR}/notices.log
EOF

# Avoid starting duplicate Tor daemons from the same portable folder.
if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE")"
  if [ -n "$PID" ] && kill -0 "$PID" >/dev/null 2>&1; then
    printf 'Tor is already running with PID %s\n' "$PID"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

printf 'Starting Tor from %s\n' "$TOR_BINARY"
printf 'Tor data directory: %s\n' "$DATA_DIR"

# RunAsDaemon makes Tor detach and write its local PID file.
"$TOR_BINARY" -f "$TORRC" --RunAsDaemon 1 "$@"

printf 'Started Tor. SOCKS proxy: 127.0.0.1:%s\n' "$SOCKS_PORT"
printf 'Tor log file: %s/notices.log\n' "$DATA_DIR"
