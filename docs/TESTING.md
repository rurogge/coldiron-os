# Testing COLDIRON OS

How the release image is verified before publishing, and how you can
repeat it.

## Release verification summary (v0.2.0)

Two layers, both green for the v0.2.0 release image:

1. **Host-side script tests — 19/19.** `coldiron-dice-seed` against the
   proven BIP39/BIP84 test vectors (zero-entropy, 24-word and non-zero
   bit-order vectors), bad-roll and rejection-sampling paths, the
   interactive flow, a PATH-stub harness proving the menu survives every
   option failure (banners reprint, exit 0), the guide render and the
   ≤76-column layout rule.
2. **QEMU/KVM full E2E — 16/16 steps, two boots.** Every menu entry was
   exercised on the real ISO:

| Step | What was verified |
|---|---|
| boot · menu render | all 8 entries (1–7 + q) with descriptions + beginner header, OCR-verified |
| opt 1 · dice-seed | warning screen → consent `n` → `Aborted.` → menu reprints (black-screen regression) |
| opt 7 · guide | plain-language guide renders → returns to menu |
| opt 4 · restore (no backups) | clean error → menu survives |
| opt 3 · backup abort | warning → consent `n` → `Aborted.` → menu survives |
| in-image battery | all 8 `coldiron-*` scripts, python3-mnemonic/ecdsa import, `--test` vectors A+B in the guest, menu via pipe, guide |
| vault prep | LUKS2 + ext4 created **inside the guest**, `blkid`-verified |
| opt 2 · unlock | via menu, passphrase via keyboard, then serial-confirmed `/mnt/vault` mounted |
| backup flow | consent → seed ×2 → 3-word spot check → age-encrypted `.age` file, sha256 verified |
| restore round-trip | `DECRYPT` → age passphrase → original seed printed **byte-exact** |
| opt 6 · shutdown | vault **mounted** → clean poweroff (qemu exited) |
| boot 2 · opt 5 | Sparrow Wallet window renders |

## Quick headless test

```sh
./scripts/qemu-test.sh dist/coldiron-os-0.2.0-amd64.iso
```

The test VM gets:

- 4 GB RAM (the `toram` boot needs it),
- a scratch 256 MB USB disk (acts as the vault — thrown away after),
- **no network device at all** (matching the appliance threat model),
- no display: the console is on stdio; `Ctrl-A X` quits.

## What a passing boot looks like

1. GRUB menu appears (640×480, theme) and boots the default entry
   (pressing `Enter` always works if the countdown doesn't auto-boot).
2. `live-boot` finds the medium and copies it to RAM (`toram`).
3. systemd reaches `multi-user.target` and `graphical.target`.
4. `getty@tty1` auto-logs in **as root** and starts X: `startx → Xorg →
   openbox → xterm "COLDIRON OS" running coldiron-menu`.
5. The menu renders with all eight lines (options 1–7 + `q`), each with a
   plain-language description, and the contextual `TIP:` line appears once
   the vault is mounted but holds no seed backups yet.

## Serial-console harness (debugging / deep tests)

The kernel cmdline has no `console=ttyS0`, so a plain `-serial stdio` VM
shows nothing. To get full boot logs and an interactive root shell, boot
the kernel directly with a serial console — no GRUB needed:

```sh
# extract the kernel + initrd from the ISO
mount -o loop,ro dist/coldiron-os-0.2.0-amd64.iso /mnt/iso
cp /mnt/iso/live/vmlinuz-* /tmp/coldiron-vmlinuz
cp /mnt/iso/live/initrd.img-* /tmp/coldiron-initrd
umount /mnt/iso

# boot with a serial console
qemu-system-x86_64 -enable-kvm -cpu host -m 4096 \
  -kernel /tmp/coldiron-vmlinuz -initrd /tmp/coldiron-initrd \
  -append 'boot=live config toram noswap noresume console=ttyS0 loglevel=6 ipv6.disable=1' \
  -cdrom dist/coldiron-os-0.2.0-amd64.iso \
  -net none -display none \
  -serial unix:/tmp/qemu-serial.sock,server=on,wait=off \
  -monitor unix:/tmp/qemu-mon.sock,server=on,wait=off &
```

Then connect to `/tmp/qemu-serial.sock` (e.g. with a small Python socket
reader) to watch the boot, and log in as `root` / `coldiron` to run
checks. The desktop is verified separately with VGA screendumps via the
QEMU monitor (`screendump` + OCR + `sendkey`).

## Known test gaps

- No automated test on **physical hardware** (only QEMU/KVM so far);
  Sparrow's import of a dice-generated seed is verified visually (the
  appliance prints the same address + fingerprint Sparrow shows).
- The GRUB `timeout=10` auto-boot works on some machines but the menu
  froze on the reference QEMU setup; pressing `Enter` always works.
- The E2E vault passphrase is the documented test password; a real
  deployment should use the full seed-ceremony checklist (see
  `docs/THREAT-MODEL.md`).
