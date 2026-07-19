#!/usr/bin/env bash
set -euo pipefail

# One-shot portable setup. The actual installers live in components/ so each
# verified download flow remains small enough to audit.
# Resolve paths from the script location instead of the caller's shell location,
# so ./install.sh always prepares the folder it lives in.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENT_DIR="${BASE_DIR}/components"

# Print one consistent fatal-error format across the top-level scripts.
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

run_component() {
  local name="$1"
  local script="${COMPONENT_DIR}/${name}.sh"

  # Components are executable scripts so they can also be run individually when
  # testing or updating one piece of the portable bundle.
  [ -x "$script" ] || die "missing executable component: $script"

  printf '\n== %s ==\n' "$name"
  (
    # Component scripts write into $PWD. Run them from BASE_DIR so their output
    # lands beside install.sh instead of wherever the user happened to be.
    cd "$BASE_DIR"
    "$script"
  )
}

# Install the verified runtimes in dependency order: Bitcoin Core gets its
# config pointing at Tor, Tor provides the local proxy, Sparrow is independent.
run_component bitcoin-core
run_component tor
run_component sparrow

# Print the important resulting paths without executing any downloaded binary.
printf '\nReady in this folder:\n'
printf '  %s/bitcoind\n' "$BASE_DIR"
printf '  %s/bitcoin-cli\n' "$BASE_DIR"
printf '  %s/bitcoin-data/bitcoin.conf\n' "$BASE_DIR"
printf '  %s/tor-runtime\n' "$BASE_DIR"
printf '  %s/sparrow-runtime\n' "$BASE_DIR"
printf '\nNext:\n'
printf '  ./start.sh\n'
printf '  ./run-sparrow.sh\n'
