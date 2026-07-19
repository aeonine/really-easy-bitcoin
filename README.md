# Really Easy Bitcoin

A portable Bitcoin validator and wallet environment with verified Bitcoin Core, bundled Tor, and Sparrow Wallet support.

Run a pruned validating node and wallet stack from one folder or USB stick, with node data, wallet app state, and Tor runtime data kept together outside `~/.bitcoin`.

[📦 Install](#install) [▶ Start](#start) [🔎 Info](#info) [🧭 Sparrow](#sparrow) [🔐 Verification](#verification)

---

## Overview

This project builds a self-contained Bitcoin self-custody workspace from verified upstream release artifacts.

It downloads Bitcoin Core, Tor Expert Bundle, and Sparrow Wallet into the current portable folder, verifies signatures and hashes, and keeps the validator, wallet runtime, and network proxy state beside the scripts.

The setup is pruned, but it is still a real Bitcoin validator: initial sync must download and validate the full blockchain history before the node is fully caught up.

The setup is designed for fast removable storage or any folder you want to move between machines. A USB M.2 SSD enclosure is strongly recommended over a cheap USB flash drive.

---

## Install

Run the installer from the portable folder:

```sh
./install.sh
```

The installer delegates to small component scripts:

- `components/bitcoin-core.sh`
- `components/tor.sh`
- `components/sparrow.sh`

Useful overrides:

```sh
BITCOIN_VERSION=31.1 ./install.sh
BITCOIN_TARGET=aarch64-linux-gnu ./install.sh
MIN_VALID_SIGNATURES=3 ./install.sh

TOR_BROWSER_VERSION=15.0.18 ./install.sh
TOR_TARGET=linux-x86_64 ./install.sh

SPARROW_VERSION=2.5.2 ./install.sh
SPARROW_TARGET=x86_64 ./install.sh
```

---

## Start

Start the local Tor daemon and Bitcoin Core node:

```sh
./start.sh
```

Stop both:

```sh
./stop.sh
```

Bitcoin Core is started with a folder-local datadir:

```sh
-datadir="$BASE_DIR/bitcoin-data"
```

---

## Info

Show node and Tor status:

```sh
./info.sh
```

`info.sh` waits through Bitcoin Core's transient startup state before printing blockchain, network, and wallet status.

---

## Sparrow

Launch Sparrow Wallet from the portable runtime:

```sh
./run-sparrow.sh
```

The launcher sets `HOME` to `sparrow-home/` for the Sparrow process, keeping Sparrow settings and wallet data in the portable folder.

`sparrow-home/` is never deleted by the install or update scripts. Updates replace `sparrow-runtime/`, not wallet/application data. The launcher also sets `sparrow-home/` permissions to owner-only.

---

## Verification

Bitcoin Core verification:

- verifies signed `SHA256SUMS`
- imports Bitcoin Core Guix builder keys
- requires valid builder signatures
- checks the selected archive hash
- copies only `bitcoind` and `bitcoin-cli`

Tor verification:

- verifies the Tor Expert Bundle signature
- pins the Tor Browser signing primary key
- accepts valid signing subkeys chained to that key
- extracts to `tor-runtime/`

Sparrow verification:

- verifies Craig Raw's signed release manifest
- checks the selected archive hash from that manifest
- extracts to `sparrow-runtime/`

---

## Security Model

This project verifies downloaded software before making it usable in the portable folder.

What is checked:

- Bitcoin Core release hashes are verified through signed `SHA256SUMS`.
- Bitcoin Core signatures are checked against imported Guix builder keys.
- Tor Expert Bundle signatures are checked against the pinned Tor Browser signing primary key.
- Sparrow archives are checked against Craig Raw's signed release manifest.
- Temporary GPG homes are used so imported verification keys do not alter your normal keyring.

What is still trusted:

- HTTPS is still required for downloads.
- The scripts trust the configured upstream URLs.
- Signing keys are downloaded from their configured key sources during install.
- Your local machine, shell, filesystem, and network environment must not already be compromised.

The scripts do not silently bypass TLS verification. If a network intercepts HTTPS, the download should fail before signature verification begins.

---

## Configuration

On first setup, the scripts create `bitcoin-data/bitcoin.conf` with portable defaults:

```ini
chain=main
server=1
daemon=1
prune=10000
dbcache=256
maxmempool=50
mempoolexpiry=24
listen=0
discover=0
maxconnections=32
proxy=127.0.0.1:9050
listenonion=0
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
debug=0
logips=0
```

Existing `bitcoin-data/bitcoin.conf` files are left untouched.

---

## Data

Runtime data stays in the portable folder:

```text
bitcoin-data/
tor-data/
sparrow-home/
```

The scripts do not use the default Bitcoin Core datadir at `~/.bitcoin`.

Treat `sparrow-home/` as sensitive wallet data. Keep backups of wallet files and seed material, and prefer hardware-wallet or watch-only workflows for meaningful funds.

---

## Update

Refresh downloaded binaries and runtimes:

```sh
./update.sh
```

The updater preserves local data folders and reruns the verified installer.

---

## Layout

After setup, the folder contains:

```text
.
├── bitcoin-cli
├── bitcoind
├── bitcoin-data/
├── components/
├── install.sh
├── start.sh
├── stop.sh
├── info.sh
├── update.sh
├── run-sparrow.sh
├── sparrow-home/
├── sparrow-runtime/
├── start-tor.sh
├── stop-tor.sh
├── tor-data/
└── tor-runtime/
```

---

## Notes

Sparrow does not currently publish an official AppImage, so this project uses Sparrow's official standalone Linux archive.

Tor Project downloads may fail on networks that intercept TLS. Use a VPN or a network without HTTPS inspection if needed.

Although this is a pruned node, initial sync still downloads and validates the full blockchain. Expect meaningful bandwidth use and plan for roughly 20-25 GB of local storage with the current defaults, based on real-world use. Exact usage can vary by Bitcoin Core version and runtime state.

Use fast external storage. A USB M.2 SSD enclosure is advised; slow flash drives can make initial validation painfully slow and may wear out faster under database writes.
