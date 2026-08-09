# COLDIRON OS

**Offline by design. Sovereign by default.**

A small, purpose-built, auditable cold-storage appliance for Bitcoin that
happens to boot from USB. COLDIRON OS is a hardened Debian 13 (Trixie)
live-build image that runs entirely from RAM, with no usable networking,
Sparrow Wallet and Bitcoin Core CLI tools preinstalled, and a companion
LUKS2-encrypted vault USB for offline PSBT signing and optional encrypted
seed backups.

> ⚠️ **STATUS: PROTOTYPE (v0.1).** Do NOT trust this ISO with a valuable
> seed yet. The v0.1 image makes networking extremely difficult to use by
> accident (driver blacklist + no network services + restrictive sysctls),
> but the kernel still contains its networking subsystem. A genuinely
> networkless kernel is the v0.2 milestone (see Roadmap). Until the
> security pass (see `docs/`) is complete, treat this as a test build.

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

## Layout

```
build.sh                                  one-command ISO builder (run as root)
scripts/
├── fetch-binaries.sh                     download + GPG-verify Sparrow (refuses without your keyring)
└── qemu-test.sh                          smoke-test the ISO in QEMU (headless)
keys/                                     YOUR trusted signing keyrings (never auto-downloaded)
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
dd if=dist/coldiron-os-0.1.0-amd64.iso of=/dev/sdX bs=4M status=progress
```

## In-image usage

| Command | Purpose |
|---|---|
| `coldiron-menu` | Launcher menu (also auto-starts with the desktop) |
| `coldiron-vault` | Unlock + mount the LUKS2 vault at `/mnt/vault` |
| `coldiron-digital-backup` | Optional age-encrypted seed backup (seed entered twice + 3-word spot check) |
| `coldiron-restore` | Decrypt a seed backup to the screen |
| `coldiron-shutdown` | Unmount, close vault, drop caches, power off |

> 🔑 **v0.1 default credentials:** the console **autologins as root** on tty1
> (the appliance is offline and RAM-only — physical possession of the USB
> is the real authentication). The documented root password for other
> ttys / serial is `coldiron`; change it with `passwd` if you rely on it.

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
  bitcoincore.org tarball with the sha256 **pinned inside
  scripts/fetch-binaries.sh** (plus a cross-check against the official
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
