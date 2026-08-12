# COLDIRON OS — Threat Model

> Applies to v0.2.0 (prototype). Read this before trusting the image with
> anything valuable. The product acceptance criteria at the bottom define
> what must be true before the PROTOTYPE banner comes off.

## What we are protecting

| Asset | Where it lives | Primary protection |
|---|---|---|
| **BIP39 seed phrase(s)** | paper/metal backups (offline), optional age-encrypted file on the vault | LUKS2 + age passphrases, physical security |
| **Wallet descriptors / xpubs** | `/vault/descriptors`, `/vault/xpubs` | LUKS2 encryption |
| **PSBTs (unsigned / signed)** | `/vault/psbt` (transported via USB) | LUKS2 encryption at rest; never on a networked machine until broadcast |
| **OS image itself** | the boot USB | read-only media, sha256-verifiable releases, auditable build |

## Assumed attacker model

1. **Remote attackers** — malware, phishing, browser exploits on a machine
   that touches Bitcoin (the "online" machine). COLDIRON OS removes the
   network so there is nothing remote to reach.
2. **Casual physical access** — a lost or stolen USB. Mitigated by LUKS2
   encryption and the absence of persistent OS state (toram).
3. **Dedicated physical adversaries** (law enforcement, theft with
   forensics) — *explicitly out of scope for v0.2*. Tamper-evident
   hardware, anti-glitch protections, and screen privacy are not addressed.

We explicitly **do not** assume that the user's own machine is trusted:
the whole point is that signing happens on a machine that has never seen
the network.

## Mitigations implemented in v0.2

- **Runs entirely from RAM** (`toram`): nothing is written back to the
  boot USB; power-off removes all OS state, history, and session data.
- **No usable networking**:
  - network/wireless/USB-ethernet/Bluetooth/FireWire/Thunderbolt drivers
    blacklisted (`/etc/modprobe.d/blacklist-coldiron.conf`),
  - loopback-only `/etc/network/interfaces`, no network services enabled,
  - IPv6 disabled, restrictive `sysctl`s (`kptr_restrict`, `dmesg_restrict`,
    BPF hardening, `kexec_load_disabled`).
  - **Limitation (prototype):** the kernel image still *contains* the
    networking subsystem as loadable modules. A compromised root shell
    could in principle load a driver and reach the network. Closing this
    — a kernel compiled without network drivers/protocols — is the
    v0.3 "product" milestone.
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
- **Verified binaries in the image**: Sparrow's release manifest is
  GPG-verified against a keyring you import out-of-band (the build
  *refuses* to auto-download keys); Bitcoin Core CLI tools are staged with
  a pinned sha256 plus a cross-check against the official SHA256SUMS.
- **Beginner guidance layer (v0.2)**: every menu entry carries a
  plain-language description, a first-time guide explains seeds/vaults/
  addresses, and scripts show a "What this does / What you need / What
  happens next" preamble before acting.
- **Auditable build**: the whole image is produced by `live-build` from
  plain-text config in this repository — no binary blobs other than the
  verified upstream artifacts.

## Honest limitations (v0.2 — the product backlog)

1. The kernel **still contains its networking subsystem** as modules —
   networking is very hard to enable *accidentally* but not impossible for
   a determined attacker with a compromised root shell. A kernel compiled
   without network drivers/protocols is the #1 product milestone.
2. **No secure boot / boot integrity verification** yet: the ISO boots via
   legacy GRUB/EFI without signature enforcement, and release artifacts are
   not yet GPG-signed by a project key. A tampered USB could in principle
   boot different code.
3. **No reproducible build yet**: `SOURCE_DATE_EPOCH`, a pinned base-image
   snapshot and a two-machine byte-diff build comparison are not yet in
   place, so you cannot yet verify that the ISO you download is
   byte-identical to what this repo produces.
4. **Bitcoin Core verification is partial**: pinned sha256 + HTTPS
   cross-check, but the `SHA256SUMS.asc` GPG signature is not yet verified
   against a user-supplied keyring (the Sparrow-style out-of-band trust
   model).
5. **AppArmor and nftables are installed but not enforced**: no mandatory
   confinement profiles, no default-deny packet policy at boot.
6. **Hardware wallets / smartcards**: `pcscd`, OpenSC and libusb are
   installed, but the workflow is not yet exercised end-to-end.
7. **Default credentials are documented** (`root` autologin on the console,
   root password `coldiron` for other ttys): physical possession of the USB
   is treated as the real authentication. Change the password with `passwd`
   if you rely on it.
8. **Screen privacy**: no privacy screen or display-locking policy is
   enforced. Shoulder-surfing is the user's responsibility.

## Product acceptance criteria (the bar for removing the PROTOTYPE banner)

A release may be declared a *product* (not a prototype) only when **all**
of the following are true and verified by the test suite:

1. **Networkless kernel**: the shipped kernel is compiled with no network
   device drivers and no loadable networking modules (loopback-only stack
   kept only because userspace — X11, dbus, udev — requires local
   sockets). Verified at boot: no network-capable device is ever probed,
   `lsmod` shows no net modules, and loading one is impossible.
2. **Verified boot path**: release artifacts are GPG-signed by the project
   signing key (SHA256SUMS.asc), and the ISO's boot files (kernel +
   initramfs) are integrity-checked by GRUB against the embedded project
   key before execution. Documented residual risk: UEFI Secure Boot
   enrollment is future work; the pre-boot sha256/signature check of the
   downloaded ISO remains the user's first control.
3. **Reproducible build**: two independent builds (local + CI) produce a
   byte-identical ISO, and the build pins its base image to a
   snapshot.debian.org date with `SOURCE_DATE_EPOCH` set.
4. **Full GPG verification of every staged binary**: Sparrow (done) and
   Bitcoin Core `SHA256SUMS.asc` (to add) are verified against keyrings the
   user imports out-of-band; the build refuses to auto-download keys.
5. **Enforced confinement**: AppArmor profiles for the appliance scripts
   are loaded and enforced at boot, and a default-deny packet policy is
   active where the kernel supports packet filtering.
6. **Documentation truth**: README, THREAT-MODEL, BUILD, INSTALL, USAGE,
   TESTING and dice-seed docs all describe the shipped release exactly —
   no stale version references, no claimed-but-missing features.
7. **Full regression**: the entire host test suite and the QEMU E2E suite
   pass on the release candidate, including the new security features.

Items 1–5 correspond to the v0.3 security pass; 6–7 are enforced on every
release.

## Operational rules the appliance enforces

- Paper/metal backup is **primary**; the digital seed backup is strictly
  tertiary and requires explicit `YES` consent plus a 3-word spot check
  against the physical backup before anything is encrypted.
- The age passphrase **must differ** from the LUKS passphrase and must be
  stored on paper, never with the USB.
- Sign only after verifying the PSBT contents on-screen; broadcast only
  from your online machine.
