# Security Policy

COLDIRON OS is a cold-storage appliance: the entire point of the project
is that a security mistake here costs people real bitcoin. We take
security reports seriously and will respond to every valid one.

## Supported versions

| Version | Status |
|---|---|
| v0.3.x | Prototype (security pass) — supported for bug reports, **not** recommended for real funds (release signing + reproducible byte-diff pending, see THREAT-MODEL.md) |
| v0.2.x | EOL — no longer supported |
| v0.1.x | EOL — no longer supported |

Once the first *product* release ships (all acceptance criteria met, see
THREAT-MODEL.md), this table will define the supported window for it.

## Reporting a vulnerability

**Do not open a public GitHub issue for security problems.** Report them
privately:

- **Preferred:** email the maintainers at the address listed on the
  release/commit signature (rurogge, GitHub `@rurogge`) — or open a
  [private security advisory](https://github.com/rurogge/coldiron-os/security/advisories/new)
  (GitHub "Report a vulnerability" — the most private channel).
- Include: affected version(s), a description of the flaw, steps to
  reproduce, and (if known) a suggested fix.

**What we promise:**

- Acknowledgement within 5 business days.
- A triage assessment (severity, affected components) within 14 days.
- Coordinated disclosure: we agree a public timeline with you before any
  announcement, and we credit you in the advisory unless you prefer
  anonymity.

## Security expectations (what this project does and does not promise)

- Every binary staged into the image is verified against a key the user
  imports out-of-band — the build refuses to trust a key fetched on the
  spot (Sparrow manifest + Bitcoin Core `SHA256SUMS.asc`, both GPG).
- The image runs from RAM, has no persistent state, and (since v0.3.0)
  ships a **networkless monolithic kernel** — no network device drivers,
  no loadable modules.
- The boot files (kernel + initramfs) are PGP-verified by GRUB before
  execution (`check_signatures=enforce`, `keys/boot/`); the appliance
  scripts run under enforced AppArmor profiles; `coldiron-check`
  (menu option 8) proves the posture at runtime.
- **Out of scope / explicitly not promised:** protection against dedicated
  physical adversaries with forensics capabilities, tamper-evident
  hardware, side-channel attacks on the hardware, and malicious BIOS/UEFI
  firmware. See [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md).

## Security-relevant files

The most security-sensitive code paths in this repository are:

- `scripts/fetch-binaries.sh` — download + GPG verification of third-party
  binaries (Sparrow, Bitcoin Core).
- `config/hooks/normal/0100-coldiron-setup.chroot` — in-image hardening
  (networking off, autologin, sysctls).
- `config/includes.chroot/etc/modprobe.d/blacklist-coldiron.conf`,
  `config/includes.chroot/etc/sysctl.d/99-coldiron.conf` — kernel-level
  attack-surface reduction.
- `config/includes.chroot/usr/local/bin/coldiron-*` — the appliance
  scripts (vault, dice-seed, backup/restore, shutdown, check).
- `config/includes.chroot/etc/apparmor.d/` — the enforced confinement
  profiles for the appliance scripts.
- `scripts/build-kernel.sh` + `scripts/kernel/networkless.config` — the
  networkless monolithic kernel build (CONFIG_NETDEVICES=n,
  CONFIG_MODULES=n).
- `scripts/sign-release.sh` + `docs/SIGNING.md` — the offline release
  signing ceremony (pending: the release key does not exist yet).
- `build.sh` / `build-docker.sh` — the build pipeline (reproducible:
  `SOURCE_DATE_EPOCH` + snapshot.debian.org pinning).
