# Testing COLDIRON OS

How the release image is verified before publishing, and how you can
repeat it.

## Release verification summary (v0.3.0)

Two layers, both green for the v0.3.0 release candidate:

1. **Host-side script tests — 27/27.** `coldiron-dice-seed` against the
   proven BIP39/BIP84 test vectors (zero-entropy, 24-word and non-zero
   bit-order vectors), bad-roll and rejection-sampling paths, the
   interactive flow (with and without passphrase, mismatch rejected), a
   PATH-stub harness proving the menu survives **every** option failure
   including the new option 8 (banners reprint, invalid choice handled,
   exit 0), the guide render and the ≤76-column layout rule.
2. **QEMU/KVM full E2E — 19/19 steps, three boots.** Every menu entry was
   exercised on the real ISO, plus a third boot through the **real GRUB
   path** proving the verified-boot chain end-to-end:

| Step | What was verified |
|---|---|
| boot · menu render | all 9 entries (1–8 + q) with descriptions + beginner header, OCR-verified |
| opt 1 · dice-seed | warning screen → consent `n` → `Aborted.` → menu reprints (black-screen regression) |
| opt 7 · guide | plain-language guide renders → returns to menu |
| opt 4 · restore (no backups) | clean error → menu survives |
| opt 3 · backup abort | warning → consent `n` → `Aborted.` → menu survives |
| opt 8 · security check | `coldiron-check` runs **all PASS** (networkless kernel, no interfaces/modules, AppArmor enforcing, boot signatures) |
| in-image battery | all 9 `coldiron-*` scripts, python3-mnemonic/ecdsa import, `--test` vectors A+B in the guest, menu via pipe, guide |
| security posture (syscheck) | serial: networkless kernel config, only `lo`, 0 `.ko` files, AppArmor ≥ 4 enforcing, boot files signed & valid |
| vault prep | LUKS2 + ext4 created **inside the guest**, `blkid`-verified |
| opt 2 · unlock | via menu, passphrase via keyboard, then serial-confirmed `/mnt/vault` mounted |
| backup flow | consent → seed ×2 → 3-word spot check → age-encrypted `.age` file, sha256 verified |
| restore round-trip | `DECRYPT` → age passphrase → original seed printed **byte-exact** |
| opt 6 · shutdown | vault **mounted** → clean poweroff (qemu exited) |
| boot 2 · opt 5 | Sparrow Wallet window renders |
| boot 3 · real GRUB | GRUB countdown → `verify_detached` + `check_signatures=enforce` → desktop reached (verified boot passed) |

## Quick headless test

```sh
./scripts/qemu-test.sh dist/coldiron-os-0.3.0-amd64.iso
```

The test VM gets:

- 4 GB RAM (the `toram` boot needs it),
- a scratch 256 MB USB disk (acts as the vault — thrown away after),
- **no network device at all** (matching the appliance threat model),
- no display: the console is on stdio; `Ctrl-A X` quits.

## What a passing boot looks like

1. GRUB menu appears (640×480, theme) and **auto-boots the default entry
   after 10 s** (pressing `Enter` always works too).
2. GRUB PGP-verifies the kernel and initramfs against the boot key;
   a tampered image refuses to boot.
3. `live-boot` finds the medium and copies it to RAM (`toram`).
4. systemd reaches `multi-user.target` and `graphical.target`.
5. `getty@tty1` auto-logs in **as root** and starts X: `startx → Xorg →
   openbox → xterm "COLDIRON OS" running coldiron-menu`.
6. The menu renders with all nine lines (options 1–8 + `q`), each with a
   plain-language description, and the contextual `TIP:` line appears once
   the vault is mounted but holds no seed backups yet.

## Serial-console harness (debugging / deep tests)

The kernel cmdline has no `console=ttyS0`, so a plain `-serial stdio` VM
shows nothing. To get full boot logs and an interactive root shell, boot
the kernel directly with a serial console — no GRUB needed:

```sh
# extract the kernel + initrd from the ISO
mount -o loop,ro dist/coldiron-os-0.3.0-amd64.iso /mnt/iso
cp /mnt/iso/live/vmlinuz-* /tmp/coldiron-vmlinuz
cp /mnt/iso/live/initrd.img-* /tmp/coldiron-initrd
umount /mnt/iso

# boot with a serial console
qemu-system-x86_64 -enable-kvm -cpu host -m 4096 \
  -kernel /tmp/coldiron-vmlinuz -initrd /tmp/coldiron-initrd \
  -append 'boot=live config toram noswap noresume console=ttyS0 loglevel=6 ipv6.disable=1' \
  -cdrom dist/coldiron-os-0.3.0-amd64.iso \
  -net none -display none \
  -serial unix:/tmp/qemu-serial.sock,server=on,wait=off \
  -monitor unix:/tmp/qemu-mon.sock,server=on,wait=off &
```

Then connect to `/tmp/qemu-serial.sock` (e.g. with a small Python socket
reader) to watch the boot, and log in as `root` / `coldiron` to run
checks. The desktop is verified separately with VGA screendumps via the
QEMU monitor (`screendump` + OCR + `sendkey`).

## The full E2E suite

`scripts/e2e/run-all.sh` runs the entire matrix above automatically
(three boots: fresh vault, Sparrow window, real GRUB path) and prints a
per-step `OK`. Run it as root:

```sh
E2E_DIR=/tmp/coldiron-e2e ./scripts/e2e/run-all.sh
```

## Known test gaps

- No automated test on **physical hardware** (only QEMU/KVM so far);
  Sparrow's import of a dice-generated seed is verified visually (the
  appliance prints the same address + fingerprint Sparrow shows).
- The **release signing** (`SHA256SUMS.asc`) and a published
  **reproducible byte-diff** (local vs CI build) are not yet part of the
  release verification — they are open acceptance criteria
  (see [THREAT-MODEL.md](THREAT-MODEL.md)).
- The E2E vault passphrase is the documented test password; a real
  deployment should use the full seed-ceremony checklist (see
  `docs/THREAT-MODEL.md`).
