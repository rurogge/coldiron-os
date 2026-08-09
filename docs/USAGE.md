# Usage Guide

The appliance is operated from the **COLDIRON launcher menu**, which
auto-starts in a terminal on the desktop:

```
══════════════════════════════════════════════
   COLDIRON OS — Offline by design. Sovereign by default.
══════════════════════════════════════════════
   1) Unlock vault
   2) Create encrypted seed backup
   3) Restore encrypted seed backup
   4) Launch Sparrow Wallet (graphical)
   5) Shut down securely
   q) Exit to shell
══════════════════════════════════════════════
```

## 1 — Unlock vault

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

## 4 — Launch Sparrow Wallet

Starts the graphical desktop (if not already running) and launches
**Sparrow Wallet 2.5.3**. Sparrow runs offline; create or import a
watch-only wallet (descriptors/xpubs) or load a hardware wallet through
the installed `pcscd`/OpenSC stack.

## The air-gapped signing workflow

1. **On your online machine**: create the transaction in your watch-only
   wallet (e.g. Sparrow), export the **unsigned PSBT**, copy it to a USB
   stick → `/vault/psbt/` (or any FAT/exFAT stick you trust).
2. **On COLDIRON OS**: unlock the vault (menu 1), launch Sparrow (menu 4),
   open the wallet, load the PSBT from `/mnt/vault/psbt/`, **verify every
   detail on screen** (amounts, addresses, fees), then sign.
3. Save the **signed PSBT** back to `/mnt/vault/psbt/`.
4. **Back on the online machine**: load the signed PSBT, finalize and
   broadcast. The private keys never left the offline machine.

## 2 — Create encrypted seed backup (OPTIONAL, tertiary only)

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

## 3 — Restore encrypted seed backup

Lists the `.age` backups in the vault (newest first), lets you choose one,
requires you to type `DECRYPT`, then prints the seed to the terminal with
the age passphrase. **Nothing is written to disk.** Write the seed down on
paper and verify it before relying on it.

## 5 — Shut down securely

Synchronizes disks, unmounts the vault, closes the LUKS container, drops
caches and powers off with `poweroff -f`. **Always use this** (or menu
`q` → `poweroff`) instead of pulling the USB out mid-session — the vault
is mounted read-write while open.

## Console commands

| Command | Purpose |
|---|---|
| `coldiron-menu` | Launcher menu (auto-starts with the desktop) |
| `coldiron-vault` | Unlock + mount the LUKS2 vault at `/mnt/vault` |
| `coldiron-digital-backup` | Optional age-encrypted seed backup |
| `coldiron-restore` | Decrypt a seed backup to the screen |
| `coldiron-shutdown` | Unmount, close vault, drop caches, power off |

## Other in-image tools

- **Bitcoin Core CLI**: `bitcoin-cli`, `bitcoin-tx`, `bitcoin-util` in
  `/opt/bitcoin/bin` (useful for raw tx inspection, e.g.
  `bitcoin-tx -json <file>`).
- **QR**: `qrencode` and `zbar-tools` for PSBT transfer via QR codes.
- **`age`** for encryption, **`paperkey`** for paper backups,
  **`wipe`** for secure deletion.
