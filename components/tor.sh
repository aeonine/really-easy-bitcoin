#!/usr/bin/env bash
set -euo pipefail

# Downloads the Tor Expert Bundle into this folder and verifies its signature.
# Defaults track the stable Tor Expert Bundle listed by the Tor Project.
# TOR_BROWSER_VERSION is the Tor Browser release that provides the expert
# bundle; the bundle itself contains the tor daemon and related runtime files.
TOR_BROWSER_VERSION="${TOR_BROWSER_VERSION:-15.0.18}"
TOR_TARGET="${TOR_TARGET:-}"

# The Tor Project publishes expert bundles on its dist host.
BASE_URL="${TOR_BASE_URL:-https://dist.torproject.org/torbrowser}"

# Verify the detached bundle signature with the expected Tor Browser signing
# key. The key URL is overrideable in case key distribution changes.
SIGNING_KEY_FINGERPRINT="${TOR_SIGNING_KEY_FINGERPRINT:-EF6E286DDA85EA2A4BA7DE684E2C6E8793298290}"
SIGNING_KEY_URL="${TOR_SIGNING_KEY_URL:-https://keys.openpgp.org/vks/v1/by-fingerprint/${SIGNING_KEY_FINGERPRINT}}"

# Extract the Tor runtime into the portable bundle root.
OUTPUT_DIR="$PWD"
RUNTIME_DIR="${OUTPUT_DIR}/tor-runtime"

# Shared fatal-error helper for clear script output.
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Fail early if a required system tool is missing.
need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

detect_target() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  # Tor expert bundle filenames use a shorter OS/architecture target string
  # than Bitcoin Core does.
  case "$os:$arch" in
    Linux:x86_64|Linux:amd64) printf 'linux-x86_64' ;;
    Darwin:x86_64) printf 'macos-x86_64' ;;
    Darwin:arm64) printf 'macos-aarch64' ;;
    *)
      die "unsupported platform $os/$arch; set TOR_TARGET manually"
      ;;
  esac
}

download() {
  local url="$1"
  local out="$2"

  printf 'Downloading %s\n' "$url"
  # Restrict downloads to HTTPS and fail on HTTP errors or TLS problems.
  curl --fail --location --proto '=https' --tlsv1.2 --output "$out" "$url"
}

# Check dependencies before fetching anything.
need curl
need gpg
need tar
need find
need rm
need chmod

if [ -z "$TOR_TARGET" ]; then
  # Default to the current machine, unless TOR_TARGET prepares another target.
  TOR_TARGET="$(detect_target)"
fi

# Build the exact archive URL for the selected Tor expert bundle.
ARCHIVE="tor-expert-bundle-${TOR_TARGET}-${TOR_BROWSER_VERSION}.tar.gz"
ARCHIVE_URL="${BASE_URL}/${TOR_BROWSER_VERSION}/${ARCHIVE}"

# Keep release files and the imported signing key out of the project folder and
# out of the user's normal GPG home.
WORKDIR="$(mktemp -d)"
GNUPGHOME_DIR="$(mktemp -d)"
export GNUPGHOME="$GNUPGHOME_DIR"

cleanup() {
  # Remove temporary downloads and the temporary GPG keyring on every exit path.
  rm -rf "$WORKDIR" "$GNUPGHOME_DIR"
}
trap cleanup EXIT

cd "$WORKDIR"

# Download the bundle, its detached signature, and the signing key used to
# verify that signature.
download "$ARCHIVE_URL" "$ARCHIVE"
download "${ARCHIVE_URL}.asc" "${ARCHIVE}.asc"
download "$SIGNING_KEY_URL" tor-browser-signing-key.asc

gpg --batch --quiet --import tor-browser-signing-key.asc

printf 'Verifying Tor Expert Bundle signature\n'
gpg --batch --status-fd 1 --verify "${ARCHIVE}.asc" "$ARCHIVE" > gpg-status.txt 2> gpg-output.txt || {
  # Show GPG's reason for failure; it is often the only useful clue.
  cat gpg-output.txt >&2
  die "Tor signature verification failed"
}

# A good signature is not enough by itself; require the expected Tor Browser
# primary key. GPG reports the signing subkey first on VALIDSIG lines and the
# primary key fingerprint later, so accept either position.
if ! awk -v fingerprint="$SIGNING_KEY_FINGERPRINT" '
  $1 == "[GNUPG:]" && $2 == "VALIDSIG" && ($3 == fingerprint || $NF == fingerprint) {
    found = 1
  }
  END {
    exit found ? 0 : 1
  }
' gpg-status.txt; then
  cat gpg-output.txt >&2
  die "signature was not made by the expected Tor Browser signing key"
fi

printf 'Signature verified with Tor Browser signing key %s\n' "$SIGNING_KEY_FINGERPRINT"

# Replace only the downloaded runtime. Persistent Tor state lives in tor-data/
# and is not touched by this component.
rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"
tar -xzf "$ARCHIVE" -C "$RUNTIME_DIR"

# Locate the actual tor daemon inside the bundle. Prefer tor/tor because the
# bundle also contains debug/tor, which is not the runtime daemon to launch.
if [ -f "${RUNTIME_DIR}/tor/tor" ]; then
  TOR_BINARY="${RUNTIME_DIR}/tor/tor"
else
  # Some archives do not preserve executable mode consistently, so find by name
  # first and chmod after. Skip debug symbols.
  TOR_BINARY="$(find "$RUNTIME_DIR" -path "${RUNTIME_DIR}/debug" -prune -o -type f -name tor -print -quit)"
fi
[ -n "$TOR_BINARY" ] || die "could not find a tor executable in $RUNTIME_DIR"
chmod 0755 "$TOR_BINARY"

printf '\nTor ready in this folder:\n'
printf '  runtime: %s\n' "$RUNTIME_DIR"
printf '  binary:  %s\n' "$TOR_BINARY"
