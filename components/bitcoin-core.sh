#!/usr/bin/env bash
set -euo pipefail

# Defaults can be overridden with environment variables, for example:
# BITCOIN_VERSION=31.1 MIN_VALID_SIGNATURES=3 ./components/bitcoin-core.sh
# VERSION selects the Bitcoin Core release; TARGET can override platform
# detection for preparing a USB folder for another machine.
VERSION="${BITCOIN_VERSION:-31.1}"
TARGET="${BITCOIN_TARGET:-}"

# Require at least one recognized builder signature by default. Raising this is
# useful if you want stricter multi-signer verification.
MIN_VALID_SIGNATURES="${MIN_VALID_SIGNATURES:-1}"

# BASE_URL points at release artifacts; KEYS_URL points at the Bitcoin Core
# Guix builder keyring used to validate the signed checksum file.
BASE_URL="${BITCOIN_BASE_URL:-https://bitcoincore.org/bin}"
KEYS_URL="${BITCOIN_KEYS_URL:-https://github.com/bitcoin-core/guix.sigs/archive/refs/heads/main.tar.gz}"

# Components write into the directory they are run from. install.sh runs them
# from the portable bundle root.
OUTPUT_DIR="$PWD"
DATA_DIR="${OUTPUT_DIR}/bitcoin-data"
CONFIG_FILE="${DATA_DIR}/bitcoin.conf"

# Abort with a clear message instead of letting a later command fail cryptically.
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Verify that a required command exists before doing any downloads.
need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

detect_target() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  # Bitcoin Core release archive names include a target triple. Keep this
  # mapping explicit so unsupported platforms fail before any download begins.
  case "$os:$arch" in
    Linux:x86_64|Linux:amd64) printf 'x86_64-linux-gnu' ;;
    Linux:aarch64|Linux:arm64) printf 'aarch64-linux-gnu' ;;
    Linux:armv7l|Linux:armhf) printf 'arm-linux-gnueabihf' ;;
    Darwin:x86_64) printf 'x86_64-apple-darwin' ;;
    Darwin:arm64) printf 'arm64-apple-darwin' ;;
    *)
      die "unsupported platform $os/$arch; set BITCOIN_TARGET manually"
      ;;
  esac
}

download() {
  local url="$1"
  local out="$2"

  printf 'Downloading %s\n' "$url"
  # HTTPS-only curl prevents accidental downgrade if a URL is changed later.
  curl --fail --location --proto '=https' --tlsv1.2 --output "$out" "$url"
}

write_default_config() {
  # Keep the Bitcoin data directory local to the portable folder.
  mkdir -p "$DATA_DIR"

  # Keep user edits intact. This config is only injected for a fresh portable
  # folder that does not already have a Bitcoin Core config.
  if [ -f "$CONFIG_FILE" ]; then
    printf 'Keeping existing config: %s\n' "$CONFIG_FILE"
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

  printf 'Wrote portable config: %s\n' "$CONFIG_FILE"
}

# These tools are intentionally boring and common: curl downloads, gpg verifies,
# tar extracts, and chmod marks the copied binaries executable.
need curl
need gpg
need awk
need tar
need chmod
need cp

# Linux commonly has sha256sum; macOS commonly has shasum.
# Use an array so the selected checker and its arguments are preserved safely.
if command -v sha256sum >/dev/null 2>&1; then
  SHA256_CHECK=(sha256sum --check)
elif command -v shasum >/dev/null 2>&1; then
  SHA256_CHECK=(shasum -a 256 --check)
else
  die "missing required command: sha256sum or shasum"
fi

if [ -z "$TARGET" ]; then
  # If the caller did not choose a target explicitly, download for this machine.
  TARGET="$(detect_target)"
fi

# Bitcoin Core publishes Linux/macOS release archives as tar.gz files. Windows
# artifacts are intentionally out of scope for these POSIX shell helpers.
case "$TARGET" in
  *-linux-*) ARCHIVE_EXT="tar.gz" ;;
  *-apple-darwin) ARCHIVE_EXT="tar.gz" ;;
  *) die "unsupported target '$TARGET'; this script extracts tar.gz release archives" ;;
esac

ARCHIVE="bitcoin-${VERSION}-${TARGET}.${ARCHIVE_EXT}"
RELEASE_DIR="bitcoin-core-${VERSION}"
RELEASE_URL="${BASE_URL}/${RELEASE_DIR}"

# Work in temporary directories so release files and imported keys do not pollute
# the project directory or the user's normal GPG keyring.
WORKDIR="$(mktemp -d)"
GNUPGHOME_DIR="$(mktemp -d)"
export GNUPGHOME="$GNUPGHOME_DIR"

cleanup() {
  # Remove both downloaded release artifacts and the temporary GPG keyring.
  rm -rf "$WORKDIR" "$GNUPGHOME_DIR"
}
trap cleanup EXIT

# Everything downloaded for verification lives in the temporary working folder.
cd "$WORKDIR"

# Download the signed checksum file, its detached signature, the selected
# release archive, and the trusted builder keys used to verify the signature.
download "${RELEASE_URL}/SHA256SUMS" SHA256SUMS
download "${RELEASE_URL}/SHA256SUMS.asc" SHA256SUMS.asc
download "${RELEASE_URL}/${ARCHIVE}" "$ARCHIVE"
download "$KEYS_URL" guix.sigs.tar.gz

# Import the Bitcoin Core builder keys used to sign SHA256SUMS.asc.
mkdir guix.sigs
tar -xzf guix.sigs.tar.gz -C guix.sigs --strip-components=1
gpg --batch --quiet --import guix.sigs/builder-keys/*.gpg

printf 'Verifying PGP signatures on SHA256SUMS.asc\n'
# SHA256SUMS.asc is a detached signature over SHA256SUMS.
# --status-fd gives machine-readable lines that we can count below.
gpg --batch --status-fd 1 --verify SHA256SUMS.asc SHA256SUMS > gpg-status.txt 2> gpg-output.txt || {
  # Surface GPG's diagnostic output before exiting, because signature failures
  # are security-relevant and should not be hidden behind a generic error.
  cat gpg-output.txt >&2
  die "PGP verification failed"
}

# Count valid signatures from imported builder keys. Raising
# MIN_VALID_SIGNATURES gives stricter plurality-style verification.
VALID_SIGNATURES="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { count++ } END { print count + 0 }' gpg-status.txt)"
if [ "$VALID_SIGNATURES" -lt "$MIN_VALID_SIGNATURES" ]; then
  cat gpg-output.txt >&2
  die "only $VALID_SIGNATURES valid signature(s); require at least $MIN_VALID_SIGNATURES"
fi
printf 'PGP verification passed with %s valid signature(s)\n' "$VALID_SIGNATURES"

printf 'Verifying SHA256 hash for %s\n' "$ARCHIVE"
# Check only the archive we downloaded, instead of asking sha256sum/shasum to
# report expected failures for every other platform listed in SHA256SUMS.
grep "  ${ARCHIVE}\$" SHA256SUMS > SHA256SUMS.selected || die "$ARCHIVE not found in SHA256SUMS"
"${SHA256_CHECK[@]}" SHA256SUMS.selected

printf 'Extracting bitcoind and bitcoin-cli\n'
# The release archive contains several tools; this project only needs the node
# daemon and CLI, so extract just those files.
tar -xzf "$ARCHIVE" \
  "bitcoin-${VERSION}/bin/bitcoind" \
  "bitcoin-${VERSION}/bin/bitcoin-cli"

# Copy the two needed binaries into the portable folder and make them runnable.
# Do not execute them here.
cp "bitcoin-${VERSION}/bin/bitcoind" "${OUTPUT_DIR}/bitcoind"
cp "bitcoin-${VERSION}/bin/bitcoin-cli" "${OUTPUT_DIR}/bitcoin-cli"
chmod 0755 "${OUTPUT_DIR}/bitcoind" "${OUTPUT_DIR}/bitcoin-cli"
write_default_config

printf '\nReady in this folder:\n'
printf '  %s/bitcoind\n' "$OUTPUT_DIR"
printf '  %s/bitcoin-cli\n' "$OUTPUT_DIR"
printf '  %s\n' "$CONFIG_FILE"
