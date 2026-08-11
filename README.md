# COLDIRON OS

**Offline by design. Sovereign by default.**

> ⚠️ **STATUS: PROTOTYPE (v0.2).** Do NOT trust this ISO with a valuable
> seed yet. The v0.1 image makes networking extremely difficult to use by
> accident (driver blacklist + no network services + restrictive sysctls),
> but the kernel still contains its networking subsystem. A genuinely
> networkless kernel is the v0.2 milestone (see Roadmap). Until the
> security pass (see `docs/`) is complete, treat this as a test build.

## Table of Contents

- [The Problem](#the-problem)
- [What COLDIRON OS is](#what-coldiron-os-is)
- [Architecture](#architecture)
- [Encryption model](#encryption-model--two-independent-layers)
- [Download](#download)
- [Quickstart](#quickstart)
- [In-image usage](#in-image-usage)
- [Documentation](#documentation)
- [Hardening notes (v0.1)](#hardening-notes-v01--honest-limitations)
- [Roadmap](#roadmap)
- [License](#license)

## The Problem

Bitcoin self-custody has a weak point that no hardware wallet fully
solves: **the moment your private keys touch a machine that has ever been
online, they are one piece of malware away from being stolen.** Most
people use a "signing laptop" that is *supposed* to stay offline — but
"supposed to" is not a security control. A single careless connection,
an OS update, a Wi-Fi auto-join, or a Bluetooth misclick is enough to
compromise years of savings.

The standard answer — a dedicated hardware wallet — is good but not
universal: devices are single-vendor black boxes, firmware updates must
be trusted, supply chains are opaque, and the device itself can become a
single point of failure (lost, dead battery, broken screen, obsolete).

**COLDIRON OS takes a different approach: make the *entire computer* the
cold wallet.** A hardened Linux distribution that boots from a USB stick
you control, runs entirely from RAM, **has no usable networking by
design**, and ships with the tools you actually need for air-gapped
Bitcoin signing:

- **Sparrow Wallet** — the most widely used open-source desktop wallet,
  preinstalled and GPG-verified,
- **Bitcoin Core CLI tools** (`bitcoin-cli`, `bitcoin-tx`, `bitcoin-util`)
  for raw transaction inspection,
- a **LUKS2-encrypted vault USB** for PSBTs, descriptors and optional
  seed backups,
- QR-code tooling, `age` encryption, hardware-wallet/smartcard support
  via OpenSC.

Because the whole OS is built from source with `live-build`, **every
line of it is auditable and reproducible by anyone** — no vendor to
trust, no firmware to update, no "just trust us" anywhere. If the network
is physically impossible to reach, the malware has no way in; if the USB
is lost, the LUKS2 vault and the paper seed backups still protect you.

## What COLDIRON OS is

A small, purpose-built, auditable cold-storage appliance for Bitcoin that
happens to boot from USB. COLDIRON OS is a hardened Debian 13 (Trixie)
live-build image that:

- runs **entirely from RAM** (`toram`) — nothing is ever written back to
  the boot USB, power-off removes all state,
- has **no usable networking** — drivers blacklisted, no network
  services, IPv6 off, restrictive sysctls,
- **autologins to a minimal desktop** with a console launcher menu,
- ships **verified binaries only** (Sparrow manifest GPG-checked against
  *your* keyring; Bitcoin Core pinned sha256 + official SHA256SUMS
  cross-check),
- pairs with a **LUKS2-encrypted vault USB** for offline PSBT signing
  and optional encrypted seed backups.

## Architecture

```
USB #1 — COLDIRON OS (bootable, read-only)
├── Debian 13 live image, boots toram (runs entirely from RAM)
├── No networking: drivers blacklisted, no network services, ipv6 off
├── No persistent logs, no swap, no core dumps, kexec disabled
├── Minimal X11/Openbox desktop + console launcher
├── Sparrow Wallet 2.5.3 (signed manifest + sha256 verified, see scripts/fetch-binaries.sh)
├── Bitcoin Core CLI tools (bitcoin-cli / bitcoin-tx / bitcoin-util)
├── QR tools (qrencode / zbar-tools), age, paperkey, wipe
└── pcscd + OpenSC + libusb for hardware-wallet / smartcard support

USB #2 — Encrypted Vault (LUKS2)
└── /vault
    ├── psbt/                    # unsigned / partially signed txs
    ├── descriptors/             # wallet output descriptors
    ├── labels/                  # wallet labels
    ├── xpubs/                   # extended public keys
    ├── encrypted-seed-backups/  # OPTIONAL age-encrypted seed files
    └── checksums/               # integrity records
```

### Encryption model — two independent layers

1. **LUKS2 container** — protects the entire vault USB if lost/stolen.
2. **age-encrypted seed file** — a separate passphrase protects the seed
   backup even if the LUKS passphrase is later compromised.

The seed backup is **strictly a tertiary recovery path**. The operational
rule is: metal plate (primary) → paper copy elsewhere (secondary) → LUKS2 +
age encrypted file (optional tertiary). The appliance forces an explicit
acknowledgement of this and verifies the physical backup before encrypting
anything digitally.

## Download

Prebuilt ISO: **[Releases](https://github.com/rurogge/coldiron-os/releases)**
→ `coldiron-os-0.1.0-amd64.iso` + `SHA256SUMS`.

```sh
sha256sum -c SHA256SUMS     # → coldiron-os-0.1.0-amd64.iso: OK
sudo dd if=coldiron-os-0.1.0-amd64.iso of=/dev/sdX bs=4M status=progress
```

Full install instructions: [docs/INSTALL.md](docs/INSTALL.md).

## Quickstart

### 1. Import the Sparrow signing key (required once)

The build **refuses** to verify Sparrow with a key downloaded on the spot —
that would defeat the purpose. Follow the official instructions
(https://sparrowwallet.com/download/ → "Verifying the Release"), then:

```sh
gpg --keyserver keyserver.ubuntu.com --recv-keys D4D0D3202FC06849A257B38DE94618334C674B40
gpg --export D4D0D3202FC06849A257B38DE94618334C674B40 \
  | gpg --no-default-keyring --keyring keys/sparrow.gpg --import
gpg --no-default-keyring --keyring keys/sparrow.gpg --fingerprint   # confirm it
```

### 2. Build

```sh
sudo ./build-root.sh            # on Debian hosts (or any host, simpler)
# or, recommended on Ubuntu hosts (trixie's own toolchain in a container):
sudo ./build-docker.sh
```

~15–60 min, needs ~10 GB disk, 4 GB+ RAM. Output: `dist/coldiron-os-0.1.0-amd64.iso`

### 3. Test in QEMU

```sh
./scripts/qemu-test.sh     # headless boot, console on stdio, Ctrl-A X to quit
```

The test VM gets a scratch 256 MB USB disk for the vault and **no network
device at all** — matching the appliance's threat model.

### 4. Write to USB

```sh
dd if=dist/coldiron-os-0.2.0-amd64.iso of=/dev/sdX bs=4M status=progress
```

## In-image usage

| Command | Purpose |
|---|---|
| `coldiron-menu` | Launcher menu (also auto-starts with the desktop) |
| `coldiron-dice-seed` | Generate a BIP39 wallet from dice rolls (+ `--test` mode) |
| `coldiron-vault` | Unlock + mount the LUKS2 vault at `/mnt/vault` |
| `coldiron-digital-backup` | Optional age-encrypted seed backup (seed entered twice + 3-word spot check) |
| `coldiron-restore` | Decrypt a seed backup to the screen |
| `coldiron-shutdown` | Unmount, close vault, drop caches, power off |
| `coldiron-guide` | First-time guide (plain language) |

> 🔑 **v0.1 default credentials:** the console **autologins as root** on tty1
> (the appliance is offline and RAM-only — physical possession of the USB
> is the real authentication). The documented root password for other
> ttys / serial is `coldiron`; change it with `passwd` if you rely on it.

## Documentation

- [docs/INSTALL.md](docs/INSTALL.md) — download, verify, write to USB, first boot, vault setup
- [docs/USAGE.md](docs/USAGE.md) — the launcher menu, dice-wallet, PSBT signing workflow, seed backup/restore
- [docs/dice-seed.md](docs/dice-seed.md) — dice entropy math, security notes, proven test vectors
- [docs/BUILD.md](docs/BUILD.md) — build from source, verification model, troubleshooting
- [docs/TESTING.md](docs/TESTING.md) — QEMU smoke test + serial-console harness
- [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md) — what this protects, against whom, honest limitations

## Repository layout

```
build.sh                                  one-command ISO builder (run as root)
scripts/
├── fetch-binaries.sh                     download + GPG-verify Sparrow + Bitcoin Core CLI (refuses without your keyring)
└── qemu-test.sh                          smoke-test the ISO in QEMU (headless)
keys/                                     YOUR trusted signing keyrings (never auto-downloaded, gitignored)
config/
├── package-lists/coldiron.list.chroot    packages installed into the image
├── hooks/normal/0100-coldiron-setup.chroot
└── includes.chroot/                      files baked into the rootfs
    ├── etc/modprobe.d/blacklist-coldiron.conf   network/peripheral driver blacklist
    ├── etc/sysctl.d/99-coldiron.conf            kernel hardening sysctls
    └── usr/local/bin/                     coldiron-vault, coldiron-digital-backup,
                                           coldiron-restore, coldiron-shutdown, coldiron-menu
dist/                                     built ISO lands here (gitignored)
```

## Hardening notes (v0.1 — honest limitations)

- `toram` + `noswap` + `noresume` + volatile logs → no persistent OS state.
- Driver blacklist (wired/wifi/USB-ethernet/Bluetooth/FireWire/Thunderbolt)
  plus loopback-only `/etc/network/interfaces` and no network services.
  This makes networking **very hard to enable accidentally** — it is not
  the same as a kernel without networking. That is v0.2.
- Restrictive sysctls: `kptr_restrict=2`, `dmesg_restrict=1`, core dumps
  disabled, `kexec_load_disabled=1`, BPF hardened, IPv6 off.
- AppArmor and nftables infrastructure present.
- The build verifies Sparrow's release manifest against **your** keyring and
  cross-checks the archive sha256. Bitcoin Core CLI tools (bitcoin-cli /
  bitcoin-tx / bitcoin-util / bitcoind) are staged from the official
  bitcoincore.org tarball with the sha256 **pinned inside**
  scripts/fetch-binaries.sh (plus a cross-check against the official
  SHA256SUMS over HTTPS). Full SHA256SUMS.asc GPG verification with your own
  keyring is part of the security pass on the roadmap.

## Roadmap

- **v0.2 — kernel-level networkless**: custom kernel with networking,
  Bluetooth and USB-network stacks compiled out entirely.
- **Security pass (before v1)**: reproducible build (live-build + SOURCE_DATE_EPOCH),
  pinned artifact hashes, independent second-machine build comparison,
  USBGuard peripheral policy, secure-boot strategy, seed-generation ceremony,
  mandatory seed transcription verification, memory-handling review,
  automated security tests, fwupd/system-update story.
- **Branding**: trademark/domain check for "COLDIRON OS" before any
  public release.
- **Release**: GitHub repo + CI reproducible build + signed ISO releases.

## License

GPL-3.0-or-later (see LICENSE).

Copyright (C) 2026 the COLDIRON OS authors.
