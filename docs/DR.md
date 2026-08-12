# COLDIRON OS — Disaster Recovery Runbook

This is the script for the worst day. **Read it once before you need it.**
Every step assumes the threat model in `docs/THREAT-MODEL.md`.

## What you have (recovery assets)

| Asset | Where | Needed for |
|---|---|---|
| Metal/paper seed words | physically separate locations | the wallet itself |
| Passphrase (if you set one) | separate paper, never with the words | spending |
| Vault USB (LUKS2) | your safe | PSBTs, descriptors, optional backups |
| age passphrase | paper, never with the USB | reading digital backups |
| COLDIRON ISO + release `.asc` | your download folder / a second USB | booting a fresh machine |

## Scenarios

### 1. Lost USB stick (the boot USB)
Boot another machine with a freshly verified ISO (`sha256sum -c` +
`gpg --verify SHA256SUMS.asc SHA256SUMS` first). Nothing about the wallet
lives on the boot USB — you only lose the appliance, not the money.

### 2. Lost vault USB
The vault is convenience, not the wallet. The seed words (metal/paper)
are the wallet. To recover a wallet from words alone:
1. Boot COLDIRON, option 5 (Sparrow) → New Wallet → Import existing →
   enter your words (+ passphrase if you set one) → Native SegWit (BIP84).
2. Compare the address/fingerprint with the self-check values you wrote
   down at creation (option 1 prints them; your notes should have them).
3. If you have an age-encrypted backup on ANOTHER medium, option 4 restores
   it after `coldiron-vault` is mounted.

### 3. Forgotten LUKS passphrase
The vault stays locked. Your seed words still work (scenario 2). If you
also lost the words, the money is gone — no backdoor exists by design.

### 4. Forgotten passphrase (the BIP39 25th word)
**Unrecoverable.** The words alone derive a different wallet. This is why
the passphrase is on paper, apart from the words. There is no recovery.

### 5. Suspected compromise (device or seed exposure)
1. Do NOT touch the old wallet further.
2. Boot a freshly verified ISO on a machine you trust.
3. Generate a NEW wallet (option 1) and move funds to it: create a PSBT
   on the new wallet, sign with the old one (swap vault USBs / import the
   old seed into Sparrow), broadcast from your online machine.
4. Assume the old seed is burned; never reuse it.

### 6. House fire / both paper backups destroyed
Recover from the age-encrypted vault backup (option 4) IF you kept the
age passphrase. This is exactly why the digital backup exists — it is
tertiary, but it is a real recovery path. If that is gone too, the money
is gone; the LUKS2 + age layers are deliberate.

## Drills (do these BEFORE you need them)

- **Quarterly**: boot the ISO, run option 8 (security check) — all green.
- **Yearly**: full restore drill — from the metal plate alone, import the
  words into a fresh Sparrow and confirm the address matches your notes.
  Do this on a machine that never goes online.
- **After any change**: re-verify the ISO (`sha256sum -c SHA256SUMS`).

## Golden rules

1. Verify the ISO before writing it to any stick. Always.
2. The words are the wallet. The passphrase is half the wallet. Both on
   paper, both offline, both in two places.
3. Nothing in this runbook can recover words that were never written down.
