# COLDIRON OS — Independent Review Guide

For the reviewer(s) asked to validate COLDIRON OS before the product
release. The review's goal is not "does it work" (the test suite proves
that) but **"does the security story hold?"** — does the appliance do what
the README claims, and is there a way to break the threat model cheaply?

## Review target

Repo: https://github.com/rurogge/coldiron-os — commit listed in the
release notes. Start with `docs/THREAT-MODEL.md` (acceptance criteria)
and `docs/BUILD.md`.

## What to review (in priority order)

1. **The networkless kernel claim** — `scripts/kernel/networkless.config`
   + `scripts/build-kernel.sh`. Does the fragment really remove every
   network device driver? Is the monolithic (no-modules) claim true of the
   shipped image (check `/proc/config.gz` + `/sys/class/net` at runtime)?
   Any remaining exfiltration channel (DMA, sideband, USB gadget)?
2. **Binary verification** — `scripts/fetch-binaries.sh` + `keys/README.md`.
   Is the out-of-band trust model sound? Is the pinned sha256 check
   meaningful alongside the GPG verification?
3. **The dice-seed entropy math** — `docs/dice-seed.md` + the embedded
   Python in `coldiron-dice-seed`: bias-free pairing, checksum handling,
   the BIP84 self-check. Any way for a flawed RNG or malformed input to
   produce a weak or wrong seed silently?
4. **Key material handling** — `coldiron-digital-backup`, `coldiron-restore`,
   `coldiron-vault`: any place a seed/passphrase could be written to disk,
   logged, or left in memory after shutdown? (toram + wipe + HISTFILE
   checks.)
5. **Boot integrity** — `keys/boot/README.md` + the grub config: is the
   documented security model (release signature = trust anchor; GRUB check
   = tamper/corruption belt) honest? Any overclaim?
6. **The scripts** — `config/includes.chroot/usr/local/bin/coldiron-*`:
   set -euo pipefail discipline, plain-language accuracy, ≤76 columns.
7. **Reproducibility** — follow `docs/BUILD.md` and the byte-diff
   procedure; the release must be reproducible.

## Threat-model lens

Read the attacker model in `docs/THREAT-MODEL.md` and ask: *"does this
still hold when the attacker has a root shell inside the VM?"* — the
appliance's own promise. Anything that gives a root-shell attacker network
access, or that leaks a seed to disk, is a finding.

## Output

A written report: findings per item (OK / concern / finding), each with
severity (critical / major / minor / nit), and a verdict on the
acceptance criteria in `docs/THREAT-MODEL.md`. Critical findings block
the release.
