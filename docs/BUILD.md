# Building COLDIRON OS from Source

The ISO is produced with `live-build` from plain-text config in this
repository — no hidden binaries. Build it yourself to verify what you
boot.

## Requirements

- **Debian 12/13 or Ubuntu 22.04+ host** (other distros: use the Docker
  path below)
- ~10 GB free disk, 4 GB+ RAM
- ~15–60 min build time (network-bound: it downloads the Debian base,
  package archives, Sparrow Wallet and Bitcoin Core binaries)
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
  staged from the official bitcoincore.org tarball. v0.1 verification is a
  **pinned sha256** inside `scripts/fetch-binaries.sh` plus a cross-check
  against the official `SHA256SUMS` over HTTPS. Full GPG verification of
  `SHA256SUMS.asc` against a user keyring is on the security-pass
  roadmap.

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

All paths produce `dist/coldiron-os-0.1.0-amd64.iso`.

## What `build.sh` does

1. Resolves prerequisites (`live-build`, `debootstrap`, ...) and
   refreshes `debian-archive-keyring` (Ubuntu's 2021 keyring cannot
   verify trixie signatures).
2. Runs `scripts/fetch-binaries.sh` — downloads and **verifies** Sparrow
   + Bitcoin Core CLI, stages them into `config/includes.chroot/opt/`.
3. Runs `lb config` with the hardening flags (see `build.sh`), then
   **forces `LB_UNION_FILESYSTEM=overlay`** in `config/chroot` (stale
   `aufs` values from earlier runs would otherwise be preserved).
4. Runs `lb clean --binary` — `lb build` does **not** detect config
   changes, so without this a stale binary stage silently produces an
   outdated ISO.
5. Runs `lb build` and moves the ISO to `dist/` with a SHA256SUMS file.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `lb config: unrecognized option '--union-filesystem'` | The option doesn't exist in live-build 2025; the overlay default is forced via `config/chroot` instead (build.sh handles it). |
| Build "succeeds" but `dist/` still has an old ISO | The binary stage was stamped done by a previous build. `lb clean --binary` in build.sh fixes it; don't remove it. |
| `apt-get remove ...` aborts mid-build | live-build runs apt non-interactively; the image includes `90coldiron-assumeyes` so removals never prompt. |
| `E: Unable to locate package bitcoin-core` | Not a Debian package (removed from Debian years ago) — the official bitcoincore.org binaries are staged instead. |
| `E: Package 'sysvinit-core' has no installation candidate` / conflicts | The generated `live.list.chroot` pins sysvinit; build.sh overrides it with the systemd variant. |
| Boot drops to BusyBox `(initramfs)` shell | The GRUB entry must contain `boot=live config` — verified in the shipped `config/bootloaders/grub-pc/config.cfg` and the bootappend in build.sh. |
| GRUB menu never auto-boots | Some machines freeze the countdown; press `Enter`. A `timeout=10` override ships in `config/bootloaders/grub-pc/config.cfg`. |

## Verifying your build

```sh
sha256sum dist/coldiron-os-0.1.0-amd64.iso
./scripts/qemu-test.sh dist/coldiron-os-0.1.0-amd64.iso   # headless smoke test
```

See [TESTING.md](TESTING.md) for the full test procedure, including the
serial-console harness used to verify the release image.
