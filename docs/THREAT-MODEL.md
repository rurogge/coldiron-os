# COLDIRON OS — Threat Model

> Applies to v0.3.0 (released — see the acceptance criteria at the
> bottom; v0.3.0's release key is a one-shot key revoked after signing,
> see [SIGNING.md](SIGNING.md)). Read this before trusting the image with
> anything valuable.

## What we are protecting

| Asset | Where it lives | Primary protection |
|---|---|---|
| **BIP39 seed phrase(s)** | paper/metal backups (offline), optional age-encrypted file on the vault | LUKS2 + age passphrases, physical security |
| **Wallet descriptors / xpubs** | `/vault/descriptors`, `/vault/xpubs` | LUKS2 encryption |
| **PSBTs (unsigned / signed)** | `/vault/psbt` (transported via USB) | LUKS2 encryption at rest; never on a networked machine until broadcast |
| **OS image itself** | the boot USB | read-only media, sha256-verifiable releases, GRUB-verified boot files, auditable build |

## Assumed attacker model

1. **Remote attackers** — malware, phishing, browser exploits on a machine
   that touches Bitcoin (the "online" machine). COLDIRON OS removes the
   network so there is nothing remote to reach.
2. **Casual physical access** — a lost or stolen USB. Mitigated by LUKS2
   encryption and the absence of persistent OS state (toram).
3. **Dedicated physical adversaries** (law enforcement, theft with
   forensics) — *explicitly out of scope for v0.3*. Tamper-evident
   hardware, anti-glitch protections, and screen privacy are not addressed.

We explicitly **do not** assume that the user's own machine is trusted:
the whole point is that signing happens on a machine that has never seen
the network.

## Mitigations implemented in v0.3

- **Runs entirely from RAM** (`toram`): nothing is written back to the
  boot USB; power-off removes all OS state, history, and session data.
- **Networkless kernel (the big one)**: the kernel is compiled from
  Debian trixie source with `scripts/kernel/networkless.config` applied:
  - `CONFIG_NETDEVICES=n` — **no network device drivers exist** in the
    kernel (NIC, tun/veth, wireless, USB-ethernet, Bluetooth, NFC, CAN…),
  - `CONFIG_MODULES=n` — **monolithic**: nothing is loadable, `/lib/modules`
    does not exist, `modprobe` has nothing it could ever load. The old
    "a compromised root shell loads a driver" attack is closed outright,
  - `CONFIG_NETFILTER=n`, `CONFIG_IPV6=n`, `CONFIG_PACKET=n` — no packet
    filter, no IPv6, no raw sockets. Loopback AF_INET and AF_UNIX stay
    (`CONFIG_NET=y`, `CONFIG_INET=y`) because udev/X11/dbus and
    Java/Sparrow need local sockets; loopback cannot reach hardware.
  - Driver blacklist and restrictive sysctls remain as defense in depth
    (belt *and* suspenders).
- **Verified boot path**: GRUB (BIOS and EFI) loads the `pgp` module
  *before* setting `check_signatures=enforce`, verifies kernel +
  initramfs against the committed boot key (`keys/boot/`), and refuses to
  execute tampered files (fails closed). The boot key detects
  tampering/corruption; it is not a trust anchor — the *release*
  signature is.
- **Enforced confinement**: AppArmor profiles for the appliance scripts
  (`coldiron-vault`, `coldiron-dice-seed`, `coldiron-digital-backup`,
  `coldiron-restore`, `coldiron-shutdown`) load and enforce at boot;
  the in-image security check (`coldiron-check`, menu option 8) asserts
  the whole posture at runtime and prints PASS/FAIL per check.
- **No persistence**: `noswap`, `noresume`, volatile `/var/log`, core
  dumps disabled, no shell history (`HISTFILE=/dev/null`).
- **Encrypted vault**: the second USB is a LUKS2 container. The seed
  backup inside is additionally encrypted with `age` under a *separate*
  passphrase (defense in depth: LUKS compromise ≠ seed compromise).
- **Dice-seed wallet (v0.2)**: BIP39 seeds generated from *physical dice
  rolls* — the computer never creates the randomness, it only assembles
  what the dice decide. Bias-free pairing (roll pairs, reject out-of-range
  values), checksum bits computed (never rolled), in-app BIP84 self-check
  derivation so the user can prove the words are right before trusting
  them, and a mandatory paper-backup verification step.
- **Full binary verification (v0.3)**: Sparrow's release manifest is
  GPG-verified against a keyring you import out-of-band; Bitcoin Core's
  `SHA256SUMS.asc` is now **also** GPG-verified against `keys/bitcoin.gpg`
  (out-of-band), with pinned sha256 as a second layer. The build *refuses*
  to auto-download keys.
- **Beginner guidance layer (v0.2)**: every menu entry carries a
  plain-language description, a first-time guide explains seeds/vaults/
  addresses, and scripts show a "What this does / What you need / What
  happens next" preamble before acting.
- **Auditable build**: the whole image is produced by `live-build` from
  plain-text config in this repository; the kernel is built from Debian
  source with a committed config fragment — no binary blobs other than
  the verified upstream artifacts.

## Honest limitations (v0.3 — the product backlog)

1. **Release signatures use a one-shot key.** The v0.3.0 `SHA256SUMS.asc`
   and ISO signatures were produced in the offline ceremony (see
   [SIGNING.md](SIGNING.md)) with a key that was **revoked immediately
   after signing** — a deliberate custody compromise (no physical air-gap
   available). The signatures verify as "Good" but the key shows as
   revoked by design; the fingerprint
   (`63EA 0A22 C16A D051 8237 8B9B 7F53 97DF 4477 C2BD`) is the
   out-of-band trust anchor, and v0.4.0 will be signed with a fresh key.
2. **Reproducible build demonstrated for v0.3.0.** The mechanism
   (`SOURCE_DATE_EPOCH`, `snapshot.debian.org` pinning, independent CI
   builder in `.github/workflows/reproducible.yml`) produced a
   byte-identical ISO on local and CI (`9bebf36f…`, verified with
   `cmp`); every future release must re-verify this before shipping.
3. **UEFI Secure Boot enrollment** is future work. GRUB's own signature
   enforcement covers the kernel/initramfs, but the bootloader itself is
   not yet anchored to machine firmware.
4. **Hardware wallets / smartcards**: `pcscd`, OpenSC and libusb are
   installed, but the workflow is not yet exercised end-to-end on real
   devices (QEMU cannot attach them).
5. **Dedicated physical adversaries** (forensics, tamper-evident
   hardware, side-channel, malicious firmware) are explicitly out of
   scope — as is **screen privacy** (shoulder-surfing is the user's
   responsibility).
6. **Default credentials are documented** (`root` autologin on the console,
   root password `coldiron` for other ttys): physical possession of the USB
   is treated as the real authentication. Change the password with `passwd`
   if you rely on it.

## Product acceptance criteria (the bar for removing the PROTOTYPE banner)

A release may be declared a *product* (not a prototype) only when **all**
of the following are true and verified by the test suite. Status as of
v0.3.0:

| # | Criterion | Status (v0.3.0) |
|---|---|---|
| 1 | **Networkless kernel**: compiled with no network device drivers and no loadable modules (loopback-only stack kept for userspace). Verified at boot: no network-capable device is ever probed, `lsmod` shows no net modules, loading one is impossible. | ✅ **DONE** — `6.12.101-coldiron`, `CONFIG_NETDEVICES=n` + `CONFIG_MODULES=n`; asserted by `coldiron-check` (menu 8) and the E2E |
| 2 | **Verified boot path**: release artifacts GPG-signed by the project signing key (`SHA256SUMS.asc`), and the ISO's boot files integrity-checked by GRUB against the embedded key before execution. | ✅ **DONE** — GRUB verification ✅ E2E-proven; `SHA256SUMS.asc` + `<iso>.asc` published on the v0.3.0 release, signed with a **one-shot** "COLDIRON OS Release" key (RSA-4096, fingerprint `63EA 0A22 C16A D051 8237 8B9B 7F53 97DF 4477 C2BD`, pubkey in `keys/release.pub`). The key was generated in an air-gapped VM, used once and **revoked immediately after signing** (deliberate custody compromise — see [SIGNING.md](SIGNING.md)); the signatures remain cryptographically valid and the fingerprint is the out-of-band trust anchor. |
| 3 | **Reproducible build**: two independent builds (local + CI) produce a byte-identical ISO; base image pinned to a `snapshot.debian.org` date with `SOURCE_DATE_EPOCH` set. | ✅ **DONE** — local build and the GitHub Actions runner both produce `9bebf36feaed981795051c8154040e5c35b1629bf8a36420ac2e57fdf3175733` (byte-identical, verified with `cmp`); see [BUILD.md](BUILD.md#reproducible-builds) |
| 4 | **Full GPG verification of every staged binary**: Sparrow and Bitcoin Core `SHA256SUMS.asc` verified against keyrings the user imports out-of-band; the build refuses to auto-download keys. | ✅ **DONE** — `keys/sparrow.gpg` + `keys/bitcoin.gpg` |
| 5 | **Enforced confinement**: AppArmor profiles loaded and enforced at boot; default-deny packet policy active where the kernel supports packet filtering. | ✅ **DONE** — enforced at boot, asserted by `coldiron-check` (networkless kernel has no packet filtering at all) |
| 6 | **Documentation truth**: README, THREAT-MODEL, BUILD, INSTALL, USAGE, TESTING and dice-seed docs all describe the shipped release exactly — no stale version references, no claimed-but-missing features. | ✅ **DONE** for v0.3.0 (2026-08-13) |
| 7 | **Full regression**: the entire host test suite and the QEMU E2E suite pass on the release candidate, including the new security features. | ✅ **DONE** — 27/27 host + 19/19 QEMU E2E (3 boots, incl. real GRUB path) |

All seven criteria are **DONE** and verified for v0.3.0 (2026-08-13):
release signing (criterion 2) and the reproducible byte-diff
(criterion 3) were completed with the release, and the PROTOTYPE banner
has been lifted. The items in "Honest limitations" above (UEFI Secure
Boot, hardware-wallet E2E, physical adversaries) are future work beyond
the product bar — not acceptance blockers.

## Operational rules the appliance enforces

- Paper/metal backup is **primary**; the digital seed backup is strictly
  tertiary and requires explicit `YES` consent plus a 3-word spot check
  against the physical backup before anything is encrypted.
- The age passphrase **must differ** from the LUKS passphrase and must be
  stored on paper, never with the USB.
- Sign only after verifying the PSBT contents on-screen; broadcast only
  from your online machine.
