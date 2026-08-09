# Testing COLDIRON OS

How the release image is smoke-tested before publishing, and how you can
repeat it.

## Quick headless test

```sh
./scripts/qemu-test.sh dist/coldiron-os-0.1.0-amd64.iso
```

The test VM gets:

- 4 GB RAM (the `toram` boot needs it),
- a scratch 256 MB USB disk (acts as the vault — thrown away after),
- **no network device at all** (matching the appliance threat model),
- no display: the console is on stdio; `Ctrl-A X` quits.

## What a passing smoke test looks like

1. GRUB menu appears (640×480, theme) and boots the default entry.
2. `live-boot` finds the medium and copies it to RAM (`toram`) — you see
   the copy progress.
3. systemd reaches `multi-user.target` and `graphical.target`.
4. `getty@tty1` auto-logs in **as root** and starts X: `startx → Xorg →
   openbox → xterm "COLDIRON OS" running coldiron-menu`.
5. The menu renders with all five options.

The v0.1.0 release image was verified this way under QEMU/KVM, including
a live session check: root login on the serial console, all five
`coldiron-*` scripts present, `/opt/sparrow/bin/Sparrow` and
`/opt/bitcoin/bin/{bitcoin-cli,bitcoin-tx}` present, **only loopback
network** (`ip -br a` → `lo`), root filesystem on `overlay` over a
read-only squashfs + tmpfs, the vault USB visible as a block device, and
~2.7 GiB free RAM after boot.

## Serial-console harness (for debugging / deeper tests)

The kernel cmdline has no `console=ttyS0`, so a plain `-serial stdio` VM
shows nothing. To get full boot logs and an interactive root shell, boot
the kernel directly with a serial console — no GRUB needed:

```sh
# extract the kernel + initrd from the ISO
mount -o loop,ro dist/coldiron-os-0.1.0-amd64.iso /mnt/iso
cp /mnt/iso/live/vmlinuz-* /tmp/coldiron-vmlinuz
cp /mnt/iso/live/initrd.img-* /tmp/coldiron-initrd
umount /mnt/iso

# boot with a serial console
qemu-system-x86_64 -enable-kvm -cpu host -m 4096 \
  -kernel /tmp/coldiron-vmlinuz -initrd /tmp/coldiron-initrd \
  -append 'boot=live config toram noswap noresume console=ttyS0 loglevel=6 ipv6.disable=1' \
  -cdrom dist/coldiron-os-0.1.0-amd64.iso \
  -net none -display none \
  -serial unix:/tmp/qemu-serial.sock,server=on,wait=off \
  -monitor unix:/tmp/qemu-mon.sock,server=on,wait=off &
```

Then connect to `/tmp/qemu-serial.sock` (e.g. with a small Python socket
reader) to watch the boot, and log in as `root` / `coldiron` to run
checks. The desktop is still verified separately with a VGA screendump
via the QEMU monitor (`screendump` + OCR).

## Known test gaps (v0.1)

- The vault **workflow** (luksFormat → unlock → PSBT sign → shutdown) is
  not yet exercised end-to-end in the automated test; the vault device is
  detected and the scripts are present, but a full dry-run is on the
  security-pass roadmap.
- No automated test on **physical hardware** (only QEMU/KVM so far).
- The GRUB `timeout=10` auto-boot works on some machines but the menu
  froze on the reference QEMU setup; pressing `Enter` always works.
