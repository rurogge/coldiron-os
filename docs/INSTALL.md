# Installation Guide

How to get COLDIRON OS onto a USB stick and boot it.

## What you need

- **USB #1 — the OS stick** (≥ 1 GB; a 4 GB stick is comfortable). All
  data on it will be destroyed.
- **USB #2 — the vault stick** (any size ≥ 64 MB; 256 MB–1 GB is typical).
  This becomes the LUKS2-encrypted vault. All data on it will be destroyed.
- An x86_64 (amd64) computer that can boot from USB. BIOS and UEFI are
  both supported by the hybrid ISO. **Secure Boot is not supported yet**
  (see the threat model / roadmap).

> ✅ **v0.3.0 is a product release** — all acceptance criteria met
> (GPG-signed artifacts + reproducible build, see
> [THREAT-MODEL.md](THREAT-MODEL.md)). Note the one-shot signing key is
> revoked by design: verify against the fingerprint
> ([SIGNING.md](SIGNING.md)).

## 1. Download

Get the ISO from the [Releases](https://github.com/rurogge/coldiron-os/releases)
page — `coldiron-os-0.3.0-amd64.iso` — and download the matching
`SHA256SUMS` file.

## 2. Verify the checksum

```sh
sha256sum -c SHA256SUMS
# coldiron-os-0.3.0-amd64.iso: OK
```

The `SHA256SUMS` file is GPG-signed (`SHA256SUMS.asc`, published on the
release) — verify it with `gpg --verify SHA256SUMS.asc SHA256SUMS` after
importing the release key (fingerprint `63EA 0A22 … 4477 C2BD`, see
[SIGNING.md](SIGNING.md)). For the strongest guarantee, build the ISO
yourself from source (see [BUILD.md](BUILD.md)) and compare hashes.

## 3. Write the ISO to the USB stick

Find your stick's device name (NOT a partition):

```sh
lsblk -o NAME,SIZE,TYPE,TRAN
```

Then write the image (replace `/dev/sdX` with your device — **this
destroys everything on it**):

```sh
sudo dd if=coldiron-os-0.3.0-amd64.iso of=/dev/sdX bs=4M status=progress
sync
```

## 4. Boot

1. Insert USB #1 and reboot.
2. Enter the boot menu (usually `F12`, `Esc`, or `F11` depending on the
   machine) and select the USB stick.
3. GRUB appears and **auto-boots the default entry after 10 seconds**.
   The kernel and initramfs are PGP-verified by GRUB before execution
   (`check_signatures=enforce`) — a tampered image refuses to boot.

The system boots **entirely from RAM** (`toram`): with 4 GB of RAM the
boot takes a couple of minutes; on slower USB sticks, longer. You'll land
on the desktop with the COLDIRON launcher menu in a terminal.

> The console **autologins as root** (the machine is offline and RAM-only;
> physical possession of the USB is the real authentication). The root
> password for other ttys / serial is `coldiron` by default — change it
> with `passwd` if you rely on it.

## 5. First-time setup: create the vault

Insert USB #2. Create the LUKS2 vault once (**destroys all data on it**):

```sh
cryptsetup luksFormat --type luks2 /dev/sdY
cryptsetup luksOpen /dev/sdY vault
mkfs.ext4 /dev/mapper/vault
cryptsetup close vault
```

(replace `/dev/sdY` with the vault stick's device). Choose a strong
passphrase and store it on paper — it is not recoverable.

From now on, `coldiron-vault` (or menu option **2**) will detect the
vault, ask for the passphrase, and mount it at `/mnt/vault` with the
appliance's directory layout (`psbt/`, `descriptors/`, `labels/`,
`xpubs/`, `encrypted-seed-backups/`, `checksums/`).

## 6. Verify the appliance is offline

The kernel has **no network device drivers and no loadable modules** —
networking is not merely disabled, it cannot exist. A quick sanity check:

```sh
ip a        # only "lo" should be present
coldiron-check   # menu option 8 — full posture check, all PASS
```

## Updating

There is no update mechanism: the OS runs from RAM and is rebuilt from
source. When a new release is out, write the new ISO to a fresh USB. Your
vault USB carries the data and is independent of the OS version.
