# Really Easy Bitcoin

Portable verified Bitcoin Core, Tor, and Sparrow setup for a folder or USB stick.

Keep the node, wallet app, Tor runtime, and all runtime data together without using `~/.bitcoin`.

[📦 Install](#install) [▶ Start](#start) [🔎 Info](#info) [🧭 Sparrow](#sparrow) [🔐 Verification](#verification)

---

## Overview

This project builds a self-contained Bitcoin workspace from verified upstream release artifacts.

It downloads Bitcoin Core, Tor Expert Bundle, and Sparrow Wallet into the current portable folder, verifies signatures and hashes, and keeps runtime state beside the scripts.

The setup is designed for removable storage or any folder you want to move between machines.

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
