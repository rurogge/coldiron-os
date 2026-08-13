# Usage Guide

The appliance is operated from the **COLDIRON launcher menu**, which
auto-starts in a terminal on the desktop:

```
══════════════════════════════════════════════════════════════════
   COLDIRON OS — your offline Bitcoin vault
   No internet needed. New here? Start with option 1 and follow in order.
══════════════════════════════════════════════════════════════════
   1) Generate seed from dice        → new wallet from your dice rolls
   2) Unlock vault                   → open the encrypted USB storage
   3) Create encrypted seed backup   → save your words, encrypted, on USB
   4) Restore encrypted seed backup  → recover a wallet from a backup
   5) Launch Sparrow Wallet          → see addresses, send and receive
   6) Shut down securely             → lock the vault and power off
   7) First-time guide               → plain-language guide (first-time)
   8) System security check          → verify the appliance is intact
   q) Exit to shell                  → leave the menu (advanced users)
══════════════════════════════════════════════════════════════════
```

Every option starts with a short **What this does / What you need / What
happens next** preamble. Beginners: run option 7 once to read the
plain-language guide, then follow options 1 → 3 → 5 in order.

## 1 — Generate seed from dice

Creates a brand-new wallet from **your dice rolls** — the computer never
generates randomness. See [docs/dice-seed.md](dice-seed.md) for the full
entropy math, security notes and proven test vectors.

Workflow, enforced by the script:

1. Warning + explicit consent (`y`).
2. Choose 12 words (52 rolls) or 24 words (104 rolls).
3. Roll pairs of dice; out-of-range pairs (33–36) are rejected and re-rolled
   (bias guard). Ctrl-C aborts at any time — nothing is kept.
4. The BIP39 seed words are printed in groups of 4 — **write them on paper,
   twice-checked**. Paper is your wallet.
5. Re-enter all words; the BIP39 checksum catches any typo.
6. **Self-check**: the appliance derives your first receive address
   (`m/84'/0'/0'/0/0`, BIP84) and the master fingerprint *before* Sparrow.
   Both must match what Sparrow shows after import.
7. Optional: back the seed up encrypted in the vault (option 3).

Non-interactive mode for verification: `coldiron-dice-seed --test rolls.txt`.

## 2 — Unlock vault

Unlocks the LUKS2 vault USB and mounts it at `/mnt/vault`. If several
LUKS devices are present you can choose which one. It creates the
appliance directory layout:

```
/mnt/vault/
├── psbt/                    # unsigned / partially signed transactions
├── descriptors/             # wallet output descriptors
├── labels/                  # wallet labels
├── xpubs/                   # extended public keys
├── encrypted-seed-backups/  # optional age-encrypted seed files
└── checksums/               # integrity records
```

Equivalent command: `coldiron-vault [device]`.

## 3 — Create encrypted seed backup (OPTIONAL, tertiary only)

> The primary recovery path is **paper/metal**. This feature creates a
> *secondary disaster-recovery copy*, encrypted twice: LUKS2 (vault) +
> `age` (separate passphrase).

Workflow, enforced by the script:

1. Explicit consent: you must type `YES` after reading the warning.
2. The vault is unlocked automatically if needed.
3. Seed entered twice (must match).
4. Word count validated (12/15/18/21/24 BIP39 words).
5. **3-word spot check** against your paper backup — a typo in the
   physical backup aborts the whole process.
6. The seed is encrypted with `age` under a **NEW passphrase** (must
   differ from the LUKS passphrase; 5+ random words recommended).
7. The plaintext temp file is securely wiped; the encrypted file is saved
   to `/mnt/vault/encrypted-seed-backups/seed-<timestamp>.age` and its
   sha256 printed.

Store the age passphrase on paper, **separate from the seed and the USB**.

## 4 — Restore encrypted seed backup

Lists the `.age` backups in the vault (newest first), lets you choose one,
requires you to type `DECRYPT`, then prints the seed to the terminal with
the age passphrase. **Nothing is written to disk.** Write the seed down on
paper and verify it before relying on it.

## 5 — Launch Sparrow Wallet

Starts the graphical desktop (if not already running) and launches
**Sparrow Wallet 2.5.3**. Sparrow runs offline; create or import a
watch-only wallet (descriptors/xpubs), import a dice-generated seed
(option 1), or load a hardware wallet through the installed `pcscd`/OpenSC
stack.

## The air-gapped signing workflow

1. **On your online machine**: create the transaction in your watch-only
   wallet (e.g. Sparrow), export the **unsigned PSBT**, copy it to a USB
   stick → `/vault/psbt/` (or any FAT/exFAT stick you trust).
2. **On COLDIRON OS**: unlock the vault (menu 2), launch Sparrow (menu 5),
   open the wallet, load the PSBT from `/mnt/vault/psbt/`, **verify every
   detail on screen** (amounts, addresses, fees), then sign.
3. Save the **signed PSBT** back to `/mnt/vault/psbt/`.
4. **Back on the online machine**: load the signed PSBT, finalize and
   broadcast. The private keys never left the offline machine.

## 6 — Shut down securely

Synchronizes disks, unmounts the vault, closes the LUKS container, drops
caches and powers off with `poweroff -f`. If unmount/close fail (device
busy) it warns and **still powers off**. **Always use this** (or menu
`q` → `poweroff`) instead of pulling the USB out mid-session — the vault
is mounted read-write while open.

## 7 — First-time guide

Renders a plain-language guide (what a seed / vault / address are, the
first-time steps, the safety rules) from `/usr/share/coldiron/guide.txt`.

## 8 — System security check

Runs `coldiron-check`, the in-image posture check that proves the
appliance matches its security model:

- kernel has **no network device drivers** and **no loadable modules**
  (`CONFIG_NETDEVICES=n`, `CONFIG_MODULES=n`),
- only the loopback interface exists,
- **AppArmor is enabled and enforcing** the appliance profiles,
- packet policy is default-deny (or no packet-filtering subsystem at
  all, on the networkless kernel),
- **boot files are signature-verified** (kernel + initramfs against the
  GRUB boot key).

Prints one PASS/FAIL line per check; exit code 0 only when everything
passes. Equivalent command: `coldiron-check [--boot-verify]`.

## Console commands

| Command | Purpose |
|---|---|
| `coldiron-menu` | Launcher menu (auto-starts with the desktop) |
| `coldiron-dice-seed` | Generate a BIP39 wallet from dice rolls (+ `--test` mode) |
| `coldiron-vault` | Unlock + mount the LUKS2 vault at `/mnt/vault` |
| `coldiron-digital-backup` | Optional age-encrypted seed backup |
| `coldiron-restore` | Decrypt a seed backup to the screen |
| `coldiron-shutdown` | Unmount, close vault, drop caches, power off |
| `coldiron-guide` | Show the first-time guide |
| `coldiron-check` | Security posture check (menu option 8) |

## Other in-image tools

- **Bitcoin Core CLI**: `bitcoin-cli`, `bitcoin-tx`, `bitcoin-util` in
  `/opt/bitcoin/bin` (useful for raw tx inspection, e.g.
  `bitcoin-tx -json <file>`).
- **QR**: `qrencode` and `zbar-tools` for PSBT transfer via QR codes.
- **`age`** for encryption, **`paperkey`** for paper backups,
  **`wipe`** for secure deletion.
