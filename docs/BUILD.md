# Building COLDIRON OS from Source

The ISO is produced with `live-build` from plain-text config in this
repository — no hidden binaries. Build it yourself to verify what you
boot.

## Requirements

- **Debian 12/13 or Ubuntu 22.04+ host** (other distros: use the Docker
  path below)
- ~10 GB free disk, 4 GB+ RAM
- ~15–60 min build time for the live image (network-bound: it downloads
  the Debian base, package archives, Sparrow Wallet and Bitcoin Core
  binaries) **plus ~30–60 min once for the networkless kernel** (cached
  afterwards as a `.deb` in `dist/kernel/`)
- `docker` (only for the `build-docker.sh` path)

## Verification model (read this first)

The image contains third-party binaries that are **verified before being
staged**:

- **Sparrow Wallet**: the release manifest is GPG-verified against a
  keyring in `keys/` that **you** import out-of-band. The build refuses
  to run with a key downloaded on the spot — that would defeat the
  purpose. One-time setup:

  ```sh
  gpg --keyserver keyserver.ubuntu.com --recv-keys D4D0D3202FC06849A257B38DE94618334C674B40
  gpg --export D4D0D3202FC06849A257B38DE94618334C674B40 \
    | gpg --no-default-keyring --keyring keys/sparrow.gpg --import
  gpg --no-default-keyring --keyring keys/sparrow.gpg --fingerprint   # confirm it
  ```

  (`keys/sparrow.gpg` is gitignored — it is *your* trust anchor, never
  published.)

- **Bitcoin Core CLI tools** (`bitcoin-cli`/`bitcoin-tx`/`bitcoin-util`):
  staged from the official bitcoincore.org tarball. The official
  `SHA256SUMS.asc` is **GPG-verified against `keys/bitcoin.gpg`** (also
  imported out-of-band — see [keys/README.md](../keys/README.md)), plus a
  pinned sha256 inside `scripts/fetch-binaries.sh` as a second layer.

- **The kernel itself**: the networkless kernel is built from Debian
  trixie **source** (`apt-get download` verifies against the Debian
  archive keyring). The only modification is the committed config
  fragment `scripts/kernel/networkless.config` — no binary blobs.

## Build

**Option A — Debian host (simplest):**

```sh
sudo ./build-root.sh
```

**Option B — Docker container (recommended on Ubuntu hosts):**

Ubuntu ships an old live-build; the container path uses Debian trixie's
own toolchain:

```sh
sudo ./build-docker.sh
```

**Option C — inside a container, manually:**

```sh
docker run --rm --privileged -v "$PWD":/build -w /build \
  -e DEBIAN_FRONTEND=noninteractive debian:trixie \
  bash -c 'apt-get update -qq && apt-get install -y -qq live-build debootstrap curl gnupg && ./build.sh'
```

All paths produce `dist/coldiron-os-0.3.0-amd64.iso`.

## What `build.sh` does

1. Resolves prerequisites (`live-build`, `debootstrap`, ...) and
   refreshes `debian-archive-keyring` (Ubuntu's 2021 keyring cannot
   verify trixie signatures).
2. Ensures the **networkless kernel package** exists — if
   `dist/kernel/linux-image-6.12.101-coldiron_*.deb` is missing it runs
   `scripts/build-kernel.sh` (~30–60 min, once; result cached and
   checksummed).
3. Runs `scripts/fetch-binaries.sh` — downloads and **verifies** Sparrow
   + Bitcoin Core CLI, stages them into `config/includes.chroot/opt/`.
4. Runs `lb config` with the hardening flags (see `build.sh`), then
   **forces `LB_UNION_FILESYSTEM=overlay`** in `config/chroot` (stale
   `aufs` values from earlier runs would otherwise be preserved).
5. Runs `lb clean --binary` — `lb build` does **not** detect config
   changes, so without this a stale binary stage silently produces an
   outdated ISO.
6. Runs `lb build` and moves the ISO to `dist/` with a SHA256SUMS file.

## The networkless kernel

`scripts/build-kernel.sh` compiles Debian trixie's `linux 6.12.101` with
the committed fragment `scripts/kernel/networkless.config`:

- `CONFIG_NETDEVICES=n` — **no** network device drivers at all (NIC, tun,
  veth, wireguard, usb-net, …), plus wireless/BT/NFC/CAN compiled out,
- `CONFIG_MODULES=n` — **monolithic**: nothing is loadable, `/lib/modules`
  does not exist in the image, `modprobe` has nothing to load,
- `CONFIG_NETFILTER=n`, `CONFIG_IPV6=n`, `CONFIG_PACKET=n` — no packet
  filter, no IPv6, no raw sockets; loopback TCP/UDP stays (`CONFIG_NET=y`,
  required by udev/X11/dbus and Java/Sparrow local sockets).

The `.deb` is reproducible (`SOURCE_DATE_EPOCH`). See the fragment header
for the full rationale and symbol list.

## Verified boot (GRUB)

The ISO's GRUB config (BIOS and EFI) loads the `pgp` module, verifies
`/live/vmlinuz-*` and `/live/initrd.img-*` against the committed boot key
(`keys/boot/`) with `verify_detached`, then sets `check_signatures=enforce`
and `timeout=10`. The files are signed at image build time by the
`9600-sign-boot` hook. The boot key's **private half is public by design**
(see `keys/boot/README.md`): it detects tampering, it is not a trust
anchor — the release signature (`SHA256SUMS.asc`, when published) is.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `lb config: unrecognized option '--union-filesystem'` | The option doesn't exist in live-build 2025; the overlay default is forced via `config/chroot` instead (build.sh handles it). |
| Build "succeeds" but `dist/` still has an old ISO | The binary stage was stamped done by a previous build. `lb clean --binary` in build.sh fixes it; don't remove it. |
| `apt-get remove ...` aborts mid-build | live-build runs apt non-interactively; the image includes `90coldiron-assumeyes` so removals never prompt. |
| `E: Unable to locate package bitcoin-core` | Not a Debian package (removed from Debian years ago) — the official bitcoincore.org binaries are staged instead. |
| `E: Package 'sysvinit-core' has no installation candidate` / conflicts | The generated `live.list.chroot` pins sysvinit; build.sh overrides it with the systemd variant. |
| Kernel build fails on `apt-get download` | Network flake or missing `deb-src` access; `build-kernel.sh` verifies against the Debian archive keyring — retry. |
| Boot drops to BusyBox `(initramfs)` shell | The GRUB entry must contain `boot=live config` — verified in the shipped `config/bootloaders/grub-pc/config.cfg` and the bootappend in build.sh. |
| GRUB refuses to boot ("signature verification failed") | Expected for a tampered image — that is the verified-boot chain failing closed. Re-flash from a verified ISO. |

## Verifying your build

```sh
sha256sum dist/coldiron-os-0.3.0-amd64.iso
./scripts/qemu-test.sh dist/coldiron-os-0.3.0-amd64.iso   # headless smoke test
```

See [TESTING.md](TESTING.md) for the full test procedure — host suite,
the 19-step QEMU E2E (3 boots, including the real GRUB path), and the
serial-console harness used to verify the release image.

## Reproducible builds

The build pins a `snapshot.debian.org` date and `SOURCE_DATE_EPOCH`
(`source-date-epoch` file in the repo root) so all timestamps are
deterministic. An independent CI builder
(`.github/workflows/reproducible.yml`) builds the same commit on GitHub
runners; comparing `sha256` of the two ISOs is the reproducibility check.
This is not yet demonstrated for a release (see
[THREAT-MODEL.md](THREAT-MODEL.md) acceptance criteria).
