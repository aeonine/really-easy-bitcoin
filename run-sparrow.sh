#!/usr/bin/env bash
set -euo pipefail

# Launch the portable Sparrow runtime with a folder-local HOME so Sparrow's
# application data does not spill into the user's normal home directory.
# Resolve from the launcher path so Sparrow stays portable even when started
# from a desktop shortcut or another working directory.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${BASE_DIR}/sparrow-runtime"
SPARROW_HOME="${BASE_DIR}/sparrow-home"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

find_sparrow() {
  # Sparrow's standalone bundle may use Sparrow or sparrow as the executable
  # name depending on packaging details.
  find "$RUNTIME_DIR" -type f \( -name Sparrow -o -name sparrow \) -print -quit
}

[ -d "$RUNTIME_DIR" ] || die "missing Sparrow runtime: $RUNTIME_DIR; run ./install.sh first"
SPARROW_BINARY="$(find_sparrow)"
[ -n "$SPARROW_BINARY" ] || die "could not find executable Sparrow binary under $RUNTIME_DIR"
chmod 0755 "$SPARROW_BINARY"

# This local HOME keeps Sparrow settings and wallet files in sparrow-home/.
mkdir -p "$SPARROW_HOME"

printf 'Launching Sparrow from %s\n' "$SPARROW_BINARY"
printf 'Sparrow home: %s\n' "$SPARROW_HOME"

# Only the launched Sparrow process sees the portable HOME value.
HOME="$SPARROW_HOME" "$SPARROW_BINARY" "$@"
