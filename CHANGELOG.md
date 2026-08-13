# Changelog

All notable user-visible changes to COLDIRON OS. See
[docs/THREAT-MODEL.md](docs/THREAT-MODEL.md) for the threat model and the
product acceptance criteria, and [docs/VERSIONING.md](docs/VERSIONING.md)
for the versioning policy.

## [v0.3.0] — 2026-08-13 — the security pass

**Status: released.** All product acceptance criteria of the threat model
are met: the release artifacts are GPG-signed (`SHA256SUMS.asc` +
`<iso>.asc`, one-shot key, fingerprint
`63EA 0A22 C16A D051 8237 8B9B 7F53 97DF 4477 C2BD`) and the
byte-reproducible build is demonstrated (local == CI == `9bebf36f…`).
Note the deliberate custody compromise: the v0.3.0 signing key was
generated in an air-gapped VM and **revoked immediately after signing**
(one-shot key, see [SIGNING.md](docs/SIGNING.md)).

### Security impact

- **Networkless monolithic kernel** (`6.12.101-coldiron`): the kernel is
  now compiled from Debian trixie source with **no network device drivers
  at all** (`CONFIG_NETDEVICES=n`, `CONFIG_WIRELESS=n`, `CONFIG_BT=n`,
  …) and **no loadable modules** (`CONFIG_MODULES=n`). The previous
  limitation — "a root shell could in principle load a driver and reach
  the network" — is closed: there is no driver to load and no module
  subsystem to load it with. Build is reproducible
  (`SOURCE_DATE_EPOCH`, committed config fragment in
  `scripts/kernel/networkless.config`).
- **Verified boot chain**: the ISO now boots GRUB (BIOS *and* EFI) with
  `pgp verify_detached` + `check_signatures=enforce` over the kernel and
  initramfs, signed at image build time with the committed boot key
  (`keys/boot/`). A tampered kernel/initramfs refuses to boot. v0.2.0's
  ISO actually booted ISOLINUX with no signature verification — fixed.
- **AppArmor enforced at boot**: confinement profiles for the appliance
  scripts (`coldiron-vault`, `coldiron-dice-seed`,
  `coldiron-digital-backup`, `coldiron-restore`, `coldiron-shutdown`)
  load and enforce on the live system (previously installed but not
  enforced). Menu option **8 — System security check** (`coldiron-check`)
  runs the full posture check in-image: networkless kernel, no
  interfaces, no modules, AppArmor, packet policy, boot-file signatures.
- **Full GPG verification of Bitcoin Core**: `SHA256SUMS.asc` is now
  verified against `keys/bitcoin.gpg` (imported out-of-band by you),
  closing the last partial binary verification.

### New / changed user-visible behavior

- New menu option **8 — System security check** (`coldiron-check`).
- GRUB auto-boots after 10 s (previously the menu could hang waiting for
  `Enter` on some machines).
- Vault enumeration fixed on PCI-based USB hosts (`USB_PCI`/`USB_XHCI_PCI`
  restored).

### Test suite

- Host-side script tests: **27/27**.
- QEMU/KVM E2E: **19/19 steps across 3 boots** — fresh vault, Sparrow
  window, and a third boot through the *real GRUB* path proving the
  verified-boot chain end-to-end.
- **Byte-reproducible ISO**: the same commit builds a byte-identical ISO
  locally and on the CI runner
  (`9bebf36feaed981795051c8154040e5c35b1629bf8a36420ac2e57fdf3175733`,
  verified with `cmp`) — acceptance criterion 3 of the threat model is
  now demonstrated. Beyond `SOURCE_DATE_EPOCH` and the pinned snapshot,
  this required normalizing the initramfs rebuild (forced epoch +
  bypassing the live-boot wrapper + `chroot_hacks` skip marker),
  uid/gid ownership (host-user uid 1001 vs root on CI, including
  usrmerge symlinks, mount-point dirs and system groups), the setuid
  bits that `chown(2)` clears, apt `pkgcache.bin` (excluded at pack
  time), and the squashfs entry order (canonical sort file). See
  [BUILD.md](docs/BUILD.md#reproducible-builds).
- ISO: `coldiron-os-0.3.0-amd64.iso` (sha256 `9bebf36f…`).

## [v0.2.0] — 2026-08-11 — dice wallet + beginner guidance

- **Dice-seed wallet**: generate a BIP39 wallet from physical dice rolls
  (bias-free pairing, checksum computed not rolled, in-app BIP84
  self-check, mandatory paper-backup verification).
- **Beginner guidance layer**: plain-language descriptions on every menu
  entry, a first-time guide, "what this does / what you need / what
  happens next" preambles, contextual tip after vault unlock.
- **Encrypted seed backup/restore**: `coldiron-digital-backup`
  (age-encrypted, separate passphrase, 3-word spot check) and
  `coldiron-restore` (decrypt to screen, nothing written to disk).
- Menu regression fix carried over from v0.1.1 (option failures never
  kill the menu).
- Test suite: 19/19 host + 16/16 QEMU E2E (2 boots).
- ISO: `coldiron-os-0.2.0-amd64.iso`.

## [v0.1.1] — 2026-08-10 — menu stability fix

- `coldiron-menu` no longer dies when an option script exits non-zero
  (a failed consent prompt or missing vault USB used to close the xterm
  → black screen). The menu now reprints and survives every failure.
- ISO: `coldiron-os-0.1.1-amd64.iso`.

## [v0.1.0] — 2026-08-09 — initial prototype

- Hardened Debian 13 (Trixie) live image: runs entirely from RAM
  (`toram`), network drivers blacklisted, no network services, IPv6 off,
  restrictive sysctls, no persistent state.
- Sparrow Wallet 2.5.3 (manifest GPG-verified against your out-of-band
  keyring), Bitcoin Core CLI tools (pinned sha256 + HTTPS cross-check),
  LUKS2 encrypted vault USB with the appliance directory layout,
  QR tooling, `age`, `paperkey`, OpenSC/hardware-wallet stack.
- ISO: `coldiron-os-0.1.0-amd64.iso`.
