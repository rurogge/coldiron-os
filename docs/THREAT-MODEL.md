# COLDIRON OS — Threat Model

> Applies to v0.1 (prototype). Read this before trusting the image with
> anything valuable.

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
   forensics) — *explicitly out of scope for v0.1*. Tamper-evident
   hardware, anti-glitch protections, and screen privacy are not addressed.

We explicitly **do not** assume that the user's own machine is trusted:
the whole point is that signing happens on a machine that has never seen
the network.

## Mitigations implemented in v0.1

- **Runs entirely from RAM** (`toram`): nothing is written back to the
  boot USB; power-off removes all OS state, history, and session data.
- **No usable networking**:
  - network/wireless/USB-ethernet/Bluetooth/FireWire/Thunderbolt drivers
    blacklisted (`/etc/modprobe.d/blacklist-coldiron.conf`),
  - loopback-only `/etc/network/interfaces`, no network services enabled,
  - IPv6 disabled, restrictive `sysctl`s (`kptr_restrict`, `dmesg_restrict`,
    BPF hardening, `kexec_load_disabled`).
- **No persistence**: `noswap`, `noresume`, volatile `/var/log`, core
  dumps disabled, no shell history (`HISTFILE=/dev/null`).
- **Encrypted vault**: the second USB is a LUKS2 container. The seed
  backup inside is additionally encrypted with `age` under a *separate*
  passphrase (defense in depth: LUKS compromise ≠ seed compromise).
- **Verified binaries in the image**: Sparrow's release manifest is
  GPG-verified against a keyring you import out-of-band (the build
  *refuses* to auto-download keys); Bitcoin Core CLI tools are staged with
  a pinned sha256 plus a cross-check against the official SHA256SUMS.
- **Auditable build**: the whole image is produced by `live-build` from
  plain-text config in this repository — no binary blobs other than the
  verified upstream artifacts.

## Honest limitations (v0.1)

- The kernel **still contains its networking subsystem** — the v0.1 image
  makes networking very hard to enable *accidentally*, but it is not
  impossible for a determined attacker who compromises the running system.
  A kernel compiled without networking is the **v0.2** milestone.
- **No secure boot** yet: the ISO boots via legacy GRUB/EFI without
  signature enforcement. A tampered USB could in principle boot different
  code. The roadmap includes a secure-boot strategy.
- **Default credentials are documented** (`root` autologin on the console,
  root password `coldiron` for other ttys): physical possession of the USB
  is treated as the real authentication. Change the password with `passwd`
  if you rely on it.
- **No reproducible build yet**: the roadmap adds `SOURCE_DATE_EPOCH`,
  pinned artifact hashes and a second-machine build comparison so you can
  verify the ISO you download is byte-identical to what the repo produces.
- **Hardware wallets / smartcards**: `pcscd`, OpenSC and libusb are
  installed, but the workflow is not yet exercised end-to-end.
- **Screen privacy**: no privacy screen or display-locking policy is
  enforced. Shoulder-surfing is the user's responsibility.

## Operational rules the appliance enforces

- Paper/metal backup is **primary**; the digital seed backup is strictly
  tertiary and requires explicit `YES` consent plus a 3-word spot check
  against the physical backup before anything is encrypted.
- The age passphrase **must differ** from the LUKS passphrase and must be
  stored on paper, never with the USB.
- Sign only after verifying the PSBT contents on-screen; broadcast only
  from your online machine.
