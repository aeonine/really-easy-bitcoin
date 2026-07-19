#!/usr/bin/env bash
set -euo pipefail

# Run Bitcoin Core from this folder, keeping blockchain data here too.
# Resolve paths from the script location so the bundle can be launched from any
# current working directory.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BITCOIND="${BASE_DIR}/bitcoind"
BITCOIN_CLI="${BASE_DIR}/bitcoin-cli"
DATA_DIR="${BASE_DIR}/bitcoin-data"
CONFIG_FILE="${DATA_DIR}/bitcoin.conf"
PID_FILE="${BASE_DIR}/bitcoind.pid"
LOG_FILE="${DATA_DIR}/debug.log"
STARTUP_WAIT_SECONDS="${STARTUP_WAIT_SECONDS:-15}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

write_default_config() {
  # Only create the default config for a fresh portable folder. Existing config
  # files may contain wallet, network, or privacy choices the user wants to keep.
  if [ -f "$CONFIG_FILE" ]; then
    return
  fi

  cat > "$CONFIG_FILE" <<'EOF'
# Core
chain=main
server=1
daemon=1

# Portable pruned node
prune=10000

# Reduce SSD/USB churn a bit
dbcache=256
maxmempool=50
mempoolexpiry=24

# Network sanity
# Outbound-only avoids port conflicts with any normal system Bitcoin Core node.
listen=0
discover=0
maxconnections=32

# Local bundled Tor proxy
# start.sh starts the in-folder Tor daemon before Bitcoin Core.
proxy=127.0.0.1:9050
listenonion=0
# Uncomment onlynet=onion if you want onion peers only.
#onlynet=onion

# RPC local only
rpcbind=127.0.0.1
rpcallowip=127.0.0.1

# Logging: less noisy
debug=0
logips=0
EOF
}

[ -x "$BITCOIND" ] || die "missing executable: $BITCOIND; run ./install.sh first"

# Create the local data directory before writing config or starting bitcoind.
mkdir -p "$DATA_DIR"
write_default_config

# Bitcoin Core's generated config points at 127.0.0.1:9050, so bring up the
# bundled Tor daemon before starting the node.
if [ -d "${BASE_DIR}/tor-runtime" ]; then
  [ -x "${BASE_DIR}/start-tor.sh" ] || die "missing executable: ${BASE_DIR}/start-tor.sh"
  "${BASE_DIR}/start-tor.sh"
else
  die "missing Tor runtime: ${BASE_DIR}/tor-runtime; run ./install.sh first"
fi

# If the PID file is present and alive, avoid starting a second node that would
# fight for the same data directory and ports.
if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE")"
  if [ -n "$PID" ] && kill -0 "$PID" >/dev/null 2>&1; then
    printf 'Bitcoin Core is already running with PID %s\n' "$PID"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

printf 'Starting Bitcoin Core from %s\n' "$BASE_DIR"
printf 'Data directory: %s\n' "$DATA_DIR"

# Extra command-line options are passed through, for example:
# ./start.sh -prune=550
# -datadir keeps all blockchain state in the portable folder.
# -pid creates a simple local process marker for status/update/stop helpers.
# -daemon returns control to the shell after Bitcoin Core starts.
"$BITCOIND" \
  -datadir="$DATA_DIR" \
  -pid="$PID_FILE" \
  -daemon \
  "$@"

# bitcoind may daemonize successfully and then fail during init. Wait until RPC
# actually answers, while tolerating Bitcoin Core's transient startup code -28.
for _ in $(seq 1 "$STARTUP_WAIT_SECONDS"); do
  if [ -f "$PID_FILE" ]; then
    PID="$(cat "$PID_FILE")"
    if [ -n "$PID" ] && kill -0 "$PID" >/dev/null 2>&1; then
      if "$BITCOIN_CLI" -datadir="$DATA_DIR" getblockchaininfo >/dev/null 2>&1; then
        printf 'Started. Log file: %s\n' "$LOG_FILE"
        exit 0
      fi
    fi
  fi
  sleep 1
done

printf 'warning: Bitcoin Core did not answer RPC within %s seconds\n' "$STARTUP_WAIT_SECONDS" >&2
printf 'Log file: %s\n' "$LOG_FILE" >&2
exit 1
