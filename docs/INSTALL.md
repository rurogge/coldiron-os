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

> ⚠️ **v0.1 is a prototype.** Do not store a valuable seed with it until
> the security pass and v0.2 (networkless kernel) are complete.

## 1. Download

Get the ISO from the [Releases](https://github.com/rurogge/coldiron-os/releases)
page — `coldiron-os-0.1.0-amd64.iso` — and download the matching
`SHA256SUMS` file.

## 2. Verify the checksum

```sh
sha256sum -c SHA256SUMS
# coldiron-os-0.1.0-amd64.iso: OK
```

The `SHA256SUMS` file itself is published alongside the release; for the
strongest guarantee, build the ISO yourself from source (see
[BUILD.md](BUILD.md)) and compare hashes.

## 3. Write the ISO to the USB stick

Find your stick's device name (NOT a partition):

```sh
lsblk -o NAME,SIZE,TYPE,TRAN
```

Then write the image (replace `/dev/sdX` with your device — **this
destroys everything on it**):

```sh
sudo dd if=coldiron-os-0.1.0-amd64.iso of=/dev/sdX bs=4M status=progress
sync
```

## 4. Boot

1. Insert USB #1 and reboot.
2. Enter the boot menu (usually `F12`, `Esc`, or `F11` depending on the
   machine) and select the USB stick.
3. GRUB appears — the default entry boots automatically after a few
   seconds. If the menu is frozen on your machine, press `Enter`.

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

From now on, `coldiron-vault` (or menu option **1**) will detect the
vault, ask for the passphrase, and mount it at `/mnt/vault` with the
appliance's directory layout (`psbt/`, `descriptors/`, `labels/`,
`xpubs/`, `encrypted-seed-backups/`, `checksums/`).

## 6. Verify the appliance is offline

The image blacklists network drivers and enables only loopback. A quick
sanity check:

```sh
ip a        # only "lo" should be present
ip route    # no default route
```

## Updating

There is no update mechanism in v0.1: the OS runs from RAM and is
rebuilt from source. When a new release is out, write the new ISO to a
fresh USB. Your vault USB carries the data and is independent of the OS
version.
