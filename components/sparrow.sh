#!/usr/bin/env bash
set -euo pipefail

# Sparrow does not currently publish an official AppImage. This downloads the
# official Linux standalone bundle and verifies it with Sparrow's signed
# manifest before extracting it into this folder.
# SPARROW_VERSION selects the release; SPARROW_TARGET can prepare x86_64 or
# aarch64 Linux bundles from another machine.
SPARROW_VERSION="${SPARROW_VERSION:-2.5.2}"
SPARROW_TARGET="${SPARROW_TARGET:-}"

# Sparrow releases live on GitHub and are authenticated by a signed manifest.
BASE_URL="${SPARROW_BASE_URL:-https://github.com/sparrowwallet/sparrow/releases/download}"

# Craig Raw's signing key is expected to sign the Sparrow release manifest.
SIGNING_KEY_FINGERPRINT="${SPARROW_SIGNING_KEY_FINGERPRINT:-D4D0D3202FC06849A257B38DE94618334C674B40}"
SIGNING_KEY_URL="${SPARROW_SIGNING_KEY_URL:-https://keybase.io/craigraw/pgp_keys.asc}"

# Extract the verified Sparrow application bundle into the portable root.
OUTPUT_DIR="$PWD"
RUNTIME_DIR="${OUTPUT_DIR}/sparrow-runtime"

# Shared fatal-error helper.
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Ensure required tools are present before networking begins.
need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

detect_target() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  # Sparrow's standalone portable bundles are Linux-only, with architecture
  # names matching the release filenames.
  case "$os:$arch" in
    Linux:x86_64|Linux:amd64) printf 'x86_64' ;;
    Linux:aarch64|Linux:arm64) printf 'aarch64' ;;
    *)
      die "unsupported platform $os/$arch; Sparrow standalone bundles are Linux-only here"
      ;;
  esac
}

download() {
  local url="$1"
  local out="$2"

  printf 'Downloading %s\n' "$url"
  # Restrict downloads to HTTPS and fail if the server returns an error.
  curl --fail --location --proto '=https' --tlsv1.2 --output "$out" "$url"
}

# Check dependencies up front so partial downloads are less likely.
need curl
need gpg
need grep
need tar
need find
need rm
need mkdir
need chmod

if command -v sha256sum >/dev/null 2>&1; then
  # --ignore-missing lets us check just the downloaded Sparrow archive even
  # though the signed manifest lists every platform artifact.
  SHA256_CHECK=(sha256sum --check --ignore-missing)
else
  die "missing required command: sha256sum"
fi

if [ -z "$SPARROW_TARGET" ]; then
  # Default to the current Linux architecture when no override is supplied.
  SPARROW_TARGET="$(detect_target)"
fi

# Construct the archive and manifest names used by Sparrow releases.
ARCHIVE="sparrowwallet-${SPARROW_VERSION}-${SPARROW_TARGET}.tar.gz"
MANIFEST="sparrow-${SPARROW_VERSION}-manifest.txt"
RELEASE_URL="${BASE_URL}/${SPARROW_VERSION}"

# Use a temporary working directory and GPG home so downloaded files and keys do
# not pollute the portable folder or the user's normal keyring.
WORKDIR="$(mktemp -d)"
GNUPGHOME_DIR="$(mktemp -d)"
export GNUPGHOME="$GNUPGHOME_DIR"

cleanup() {
  # Remove temporary release artifacts and the temporary GPG keyring.
  rm -rf "$WORKDIR" "$GNUPGHOME_DIR"
}
trap cleanup EXIT

cd "$WORKDIR"

# Download the signed manifest, the selected Sparrow archive, and the signing
# key used to authenticate the manifest.
download "${RELEASE_URL}/${MANIFEST}" "$MANIFEST"
download "${RELEASE_URL}/${MANIFEST}.asc" "${MANIFEST}.asc"
download "${RELEASE_URL}/${ARCHIVE}" "$ARCHIVE"
download "$SIGNING_KEY_URL" sparrow-signing-key.asc

gpg --batch --quiet --import sparrow-signing-key.asc

printf 'Verifying Sparrow manifest signature\n'
gpg --batch --status-fd 1 --verify "${MANIFEST}.asc" "$MANIFEST" > gpg-status.txt 2> gpg-output.txt || {
  # Preserve GPG diagnostics for auditing signature failures.
  cat gpg-output.txt >&2
  die "Sparrow manifest signature verification failed"
}

# Require the expected signer fingerprint, not just any valid OpenPGP signature.
# GPG reports the signing subkey first on VALIDSIG lines and the primary key
# fingerprint later, so accept either position.
if ! awk -v fingerprint="$SIGNING_KEY_FINGERPRINT" '
  $1 == "[GNUPG:]" && $2 == "VALIDSIG" && ($3 == fingerprint || $NF == fingerprint) {
    found = 1
  }
  END {
    exit found ? 0 : 1
  }
' gpg-status.txt; then
  cat gpg-output.txt >&2
  die "manifest was not signed by the expected Sparrow signing key"
fi

printf 'Signature verified with Sparrow signing key %s\n' "$SIGNING_KEY_FINGERPRINT"

printf 'Verifying SHA256 hash for %s\n' "$ARCHIVE"
# Check only the selected archive line from the signed manifest. sha256sum
# manifests may separate the hash and filename with spaces, or use *filename
# for binary-mode entries, so match the filename field rather than hard-coding
# one exact spacing style.
awk -v archive="$ARCHIVE" '
  $2 == archive || $2 == "*" archive {
    print
    found = 1
  }
  END {
    exit found ? 0 : 1
  }
' "$MANIFEST" > manifest.selected || die "$ARCHIVE not found in $MANIFEST"
"${SHA256_CHECK[@]}" manifest.selected

# Replace the application runtime while preserving sparrow-home/ user data.
rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"
tar -xzf "$ARCHIVE" -C "$RUNTIME_DIR" --strip-components=1

# Find the launchable Sparrow binary inside the extracted standalone bundle.
# Like Tor, archive modes can vary, so find by name first and chmod after.
SPARROW_BINARY="$(find "$RUNTIME_DIR" -type f \( -name Sparrow -o -name sparrow \) -print -quit)"
[ -n "$SPARROW_BINARY" ] || die "could not find a Sparrow executable in $RUNTIME_DIR"
chmod 0755 "$SPARROW_BINARY"

printf '\nSparrow ready in this folder:\n'
printf '  runtime: %s\n' "$RUNTIME_DIR"
printf '  binary:  %s\n' "$SPARROW_BINARY"
