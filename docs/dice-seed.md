# Dice-Seed Wallet (v0.2, shipped since v0.2.0 — current: v0.3.0)

Generate a brand-new Bitcoin wallet from **physical dice rolls** — no computer
randomness involved. This makes COLDIRON a Coldcard-style "dice wallet".

## How it works

1. You roll two dice and type the faces. Pairs are mapped to 5 unbiased bits.
2. After 26 pairs (12 words) or 52 pairs (24 words) the entropy is complete.
3. The seed words are derived with the standard BIP39 wordlist
   (`python3-mnemonic` — the library used by Electrum).
4. You write the words on paper (that is your wallet), then re-enter them.
   The BIP39 checksum catches any typo.
5. A **self-check** derives your first receive address
   (`m/84'/0'/0'/0/0`, BIP84 native SegWit) and the master fingerprint
   in-app — before you ever touch Sparrow. Both must match what Sparrow
   shows after import.

## The entropy math (honest numbers)

| Words | Entropy | Pairs | Rolls | Bits produced | Discarded |
|---|---|---|---|---|---|
| 12 | 128 bits | 26 | 52 | 130 | 2 |
| 24 | 256 bits | 52 | 104 | 260 | 4 |

- Pair value `v = (dieA−1)·6 + (dieB−1)` ∈ 0…35. Values 0–31 are kept
  (5 bits); **33–36 are rejected** and re-rolled. This removes mapping bias
  completely — *for a fair die*.
- The checksum bits are computed (SHA256), never rolled.
- 52 rolls ≈ 128 bits of min-entropy **only if the die is fair**. Use
  casino-grade dice (sharp corners, uniform pips). A chi-square sanity check
  is planned for v2.

## Security notes

- The seed exists only in RAM and on your paper. Shutdown wipes it (toram).
- Never photograph the words; never type them into an online device.
- Paper is the PRIMARY backup. The encrypted vault copy (menu option 3) is
  strictly secondary — use a different passphrase for it.
- The self-check derivation lives entirely in the appliance:
  `python3-mnemonic` (BIP39), `python3-ecdsa` (secp256k1), plus ~70 lines of
  in-script BIP32/bech32 code. The derivation was verified byte-exact
  against the official BIP39/BIP84 test vectors.

## Proven test vectors (used by the E2E suite)

| Rolls (die faces, one per line) | Expected mnemonic | Expected address |
|---|---|---|
| `1` × 52 | `abandon` ×11 + `about` | `bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu` |
| Vector B (non-zero, see plan) | `abandon amount liar amount expire adjust cage candy arch gather drum buyer` | — |

Non-interactive check: `coldiron-dice-seed --test rolls.txt` prints
`MNEMONIC:` / `ADDRESS:` / `FINGERPRINT:` lines for assertion.

## BIP39 passphrase

An optional extra passphrase (hidden 13th/25th factor, e.g. extra dice words)
is planned for v2. The generated seed is compatible with it — the words
themselves are standard BIP39.
