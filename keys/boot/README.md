# keys/boot/ — COLDIRON boot-signing key (BUILD COMPONENT, not a trust anchor)

`boot.sec` + `boot.pub` form the keypair used to sign the kernel and
initramfs that GRUB loads, so the ISO's GRUB config can verify them
(`check_signatures=enforce`) before execution, and `coldiron-check` can
re-verify them at runtime.

## ⚠️ Read this before worrying about the private key in this repo

**The private key `boot.sec` is committed on purpose, and it is NOT a
trust anchor.** Anyone can read it — including any attacker. The security
of the appliance does NOT rest on this key. It exists only to make the
GRUB signature check *possible* while keeping builds reproducible (a
random per-build key would make every ISO byte-different and kill the
reproducible-build guarantee).

The real authenticity chain is:

1. **You verify the release before writing the USB** — `sha256sum -c
   SHA256SUMS` + GPG-verify `SHA256SUMS.asc` against the project release
   signing key (see `docs/SIGNING.md`). This is what proves the ISO is
   genuinely from the COLDIRON project.
2. **GRUB checks the boot files against `boot.pub` embedded in the ISO.**
   This catches corruption and in-place tampering with the kernel/initramfs
   on a USB that was already verified (the boot files no longer match what
   the verified ISO contained).
3. **UEFI Secure Boot** (roadmap) is what will close the remaining gap:
   an attacker re-mastering a *new* ISO with their own boot key. Until
   then, a fully re-mastered stick is caught by re-running step 1.

An attacker who can re-master the ISO can trivially re-sign the boot
files with this known key — but a re-mastered ISO has a different sha256
and fails the release signature check. That is the boundary of this
mechanism, and it is honest about it.

## Regenerating

```sh
gpg --batch --pinentry-mode loopback --passphrase '' \
  --quick-gen-key "COLDIRON OS Boot Key (build component) <boot@coldiron-os.invalid>" \
  rsa4096 sign 0
# export armored keypair as keys/boot/boot.pub / boot.sec, update
# config/includes.chroot/usr/share/coldiron/boot-key.pub, commit together.
```

## How it is used

- `config/hooks/normal/9600-sign-boot.chroot` — signs `/boot/vmlinuz-*`
  and `/boot/initrd.img-*` inside the build chroot (`.sig` next to each),
  using a temporary copy of `boot.sec` that is deleted before the
  rootfs is packed. The temporary copy comes from
  `config/includes.chroot/usr/share/coldiron/boot.sec` and never ships.
- `config/hooks/binary/*.hook.binary` — signs the ISO's `/live/vmlinuz`
  and `/live/initrd.img` (the exact files GRUB loads) and drops
  `boot.pub` next to them.
- `config/bootloaders/grub-pc/grub.cfg` — `trust` + `verify_detached` +
  `check_signatures=enforce` before the `linux`/`initrd` lines.
- `coldiron-check` — runtime re-verification of `/boot/vmlinuz-*` against
  the embedded public key (`/usr/share/coldiron/boot-key.pub`).

## Security rule

If you ever see this key used to sign anything other than the boot files
of a COLDIRON build, or used as a trust anchor anywhere, that is a bug.
Report it (see SECURITY.md).
