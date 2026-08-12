#!/bin/bash
# scripts/host-tests.sh — host-side verification of the COLDIRON scripts.
#
# Runs the dice-seed derivation against proven BIP39/BIP84 test vectors
# (zero-entropy, 24-word, non-zero bit-order, passphrase), the interactive
# flow, bad-roll/rejection-sampling paths, the menu survival harness and
# the ≤76-column layout rule.
#
# Usage:  ./scripts/host-tests.sh
# Environment:
#   VENE — venv/bin dir with python3-mnemonic + python3-ecdsa for the host
#          (default: /tmp/dicecheck/bin if present, else system python3)
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/config/includes.chroot/usr/local/bin"
HARNESS="$(mktemp -d /tmp/coldiron-harness.XXXXXX)"
trap 'rm -rf "$HARNESS"' EXIT
if [ -x /tmp/dicecheck/bin/python ]; then
  VENE="${VENE:-/tmp/dicecheck/bin}"
else
  VENE="${VENE:-}"
fi
OK=0; BAD=0
ok()  { OK=$((OK+1)); echo "  PASS: $1"; }
bad() { BAD=$((BAD+1)); echo "  FAIL: $1"; }
mkdir -p "$HARNESS/fakebin"

# ---------- roll vector files ----------
: > "$HARNESS/vecA.txt";   for i in $(seq 1 52);  do echo 1 >> "$HARNESS/vecA.txt"; done
: > "$HARNESS/vec24.txt";  for i in $(seq 1 104); do echo 1 >> "$HARNESS/vec24.txt"; done
: > "$HARNESS/vecB.txt"
for f in 1 1 1 1 1 1 3 5 1 5 1 1 5 1 1 5 1 1 4 3 1 4 1 1 3 3 1 3 1 1 2 4 1 2 2 3 1 6 3 5 5 1 1 4 2 3 3 3 1 2 5 5; do echo "$f" >> "$HARNESS/vecB.txt"; done

PHRASE_A="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
PHRASE_24="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
PHRASE_B="abandon amount liar amount expire adjust cage candy arch gather drum buyer"
DS() { PATH="$VENE:$PATH" COLDIRON_LIB="$BIN/coldiron-lib" "$BIN/coldiron-dice-seed" "$@"; }

echo "=== dice-seed --test: Vector A (52×1) ==="
OUT=$(DS --test "$HARNESS/vecA.txt" 2>&1)
echo "$OUT" | grep -q "MNEMONIC:$PHRASE_A" && ok "A: mnemonic" || bad "A: mnemonic -> $OUT"
echo "$OUT" | grep -q "ADDRESS:bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu" && ok "A: address" || bad "A: address -> $OUT"
echo "$OUT" | grep -q "FINGERPRINT:73c5da0a" && ok "A: fingerprint" || bad "A: fingerprint -> $OUT"

echo "=== dice-seed --test: Vector A + passphrase (BIP39 TREZOR vector) ==="
OUT=$(DS --test "$HARNESS/vecA.txt" "TREZOR" 2>&1)
echo "$OUT" | grep -q "SEED:c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04" \
  && ok "A+TREZOR: seed matches official BIP39 vector" || bad "A+TREZOR: seed -> $OUT"
echo "$OUT" | grep -q "ADDRESS:bc1qv5rmq0kt9yz3pm36wvzct7p3x6mtgehjul0feu" && ok "A+TREZOR: address" || bad "A+TREZOR: address -> $OUT"
echo "$OUT" | grep -q "FINGERPRINT:b4e3f5ed" && ok "A+TREZOR: fingerprint" || bad "A+TREZOR: fingerprint -> $OUT"

echo "=== dice-seed --test: 24-word (104×1) ==="
OUT=$(DS --test "$HARNESS/vec24.txt" 2>&1)
echo "$OUT" | grep -q "MNEMONIC:$PHRASE_24" && ok "24w: mnemonic" || bad "24w: mnemonic -> ${OUT:0:120}"

echo "=== dice-seed --test: Vector B (non-zero, bit-order check) ==="
OUT=$(DS --test "$HARNESS/vecB.txt" 2>&1)
echo "$OUT" | grep -q "MNEMONIC:$PHRASE_B" && ok "B: mnemonic (bit-order ok)" || bad "B: mnemonic -> $OUT"

echo "=== dice-seed --test: bad roll rejected ==="
printf '7\n' > "$HARNESS/bad.txt"
OUT=$(DS --test "$HARNESS/bad.txt" 2>&1); RC=$?
[ "$RC" -eq 2 ] && echo "$OUT" | grep -q "BADROLL" && ok "bad roll: exit 2 + BADROLL" || bad "bad roll: rc=$RC out=$OUT"

echo "=== dice-seed --test: rejection sampling (pair 6,6 = 35) skipped ==="
printf '6\n6\n' > "$HARNESS/rej.txt"
for i in $(seq 1 52); do echo 1 >> "$HARNESS/rej.txt"; done   # 54 faces = 27 pairs, 1 rejected → 26 valid
OUT=$(DS --test "$HARNESS/rej.txt" 2>&1); RC=$?
echo "$OUT" | grep -q "MNEMONIC:$PHRASE_A" && ok "rejection: still derives Vector A" || bad "rejection: rc=$RC -> $OUT"

echo "=== dice-seed INTERACTIVE flow (consent, 12w, rolls, re-entry, no passphrase, backup=n) ==="
{ echo y; echo 12; yes 1 | head -52; echo "$PHRASE_A"; echo n; echo n; } | DS > "$HARNESS/int.out" 2>&1
grep -q "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu" "$HARNESS/int.out" && ok "interactive: address" || bad "interactive: address"
grep -q "73c5da0a" "$HARNESS/int.out" && ok "interactive: fingerprint" || bad "interactive: fingerprint"
grep -q "✅ Done" "$HARNESS/int.out" && ok "interactive: completed" || bad "interactive: no Done"

echo "=== dice-seed INTERACTIVE with passphrase (words alone ≠ words+passphrase) ==="
PP="my cold storage phrase"
PP_ADDR=$(DS --test "$HARNESS/vecA.txt" "$PP" 2>&1 | grep '^ADDRESS:' | cut -d: -f2-)
{ echo y; echo 12; yes 1 | head -52; echo "$PHRASE_A"; echo y; echo "$PP"; echo "$PP"; echo n; } \
  | DS > "$HARNESS/intpp.out" 2>&1
grep -q "${PP_ADDR}" "$HARNESS/intpp.out" && ok "interactive+passphrase: address matches --test derivation" \
  || bad "interactive+passphrase: expected ${PP_ADDR} -> $(grep -oE 'bc1q[a-z0-9]+' "$HARNESS/intpp.out" | head -1)"
grep -q "✅ Done" "$HARNESS/intpp.out" && ok "interactive+passphrase: completed" || bad "interactive+passphrase: no Done"
grep -q "words alone give a DIFFERENT address" "$HARNESS/intpp.out" && ok "interactive+passphrase: warning shown" \
  || bad "interactive+passphrase: warning missing"

echo "=== dice-seed INTERACTIVE: passphrase mismatch rejected ==="
{ echo y; echo 12; yes 1 | head -52; echo "$PHRASE_A"; echo y; echo "one"; echo "two"; echo n; echo n; } \
  | DS > "$HARNESS/intpp2.out" 2>&1
grep -q "The two entries differ" "$HARNESS/intpp2.out" && ok "passphrase mismatch: rejected with message" \
  || bad "passphrase mismatch: no error -> $(tail -3 "$HARNESS/intpp2.out")"

echo "=== menu harness: every option fails → menu survives ==="
for s in coldiron-dice-seed coldiron-vault coldiron-digital-backup coldiron-restore coldiron-shutdown coldiron-guide coldiron-check startx; do
  printf '#!/bin/bash\necho "STUB %s called"\nexit 1\n' "$s" > "$HARNESS/fakebin/$s"
  chmod +x "$HARNESS/fakebin/$s"
done
printf '#!/bin/bash\nexit 0\n' > "$HARNESS/fakebin/mountpoint"; chmod +x "$HARNESS/fakebin/mountpoint"
printf '1\n2\n3\n4\n5\n6\n7\n8\nx\nq\n' | PATH="$HARNESS/fakebin:$PATH" COLDIRON_LIB="$BIN/coldiron-lib" \
  "$BIN/coldiron-menu" > "$HARNESS/menu.out" 2>&1; RC=$?
[ "$RC" -eq 0 ] && ok "menu: exit 0" || bad "menu: rc=$RC"
BANNERS=$(grep -c "COLDIRON OS — your offline Bitcoin vault" "$HARNESS/menu.out")
[ "$BANNERS" -ge 10 ] && ok "menu: banner reprinted after every failure ($BANNERS)" || bad "menu: banners=$BANNERS"
grep -q "STUB coldiron-dice-seed called" "$HARNESS/menu.out" && ok "menu: option 1 invoked" || bad "menu: option 1 not invoked"
grep -q "STUB coldiron-guide called" "$HARNESS/menu.out" && ok "menu: option 7 invoked" || bad "menu: option 7 not invoked"
grep -q "STUB coldiron-check called" "$HARNESS/menu.out" && ok "menu: option 8 invoked" || bad "menu: option 8 not invoked"
grep -q "Invalid choice." "$HARNESS/menu.out" && ok "menu: invalid choice handled" || bad "menu: invalid choice"
grep -q "TIP: no seed backups in the vault yet" "$HARNESS/menu.out" && ok "menu: contextual tip shown (vault mounted, empty)" || bad "menu: tip missing"

echo "=== guide render ==="
printf '\n' | COLDIRON_LIB="$BIN/coldiron-lib" GUIDE_FILE="$REPO/config/includes.chroot/usr/share/coldiron/guide.txt" \
  "$BIN/coldiron-guide" > "$HARNESS/guide.out" 2>&1
grep -q "What is a seed?" "$HARNESS/guide.out" && ok "guide: renders" || bad "guide: not rendered"
AW=$(awk 'length > 76 {print length": "$0}' "$REPO/config/includes.chroot/usr/share/coldiron/guide.txt")
[ -z "$AW" ] && ok "guide: all lines ≤ 76 cols" || bad "guide: wide lines -> $AW"
MW=$(awk 'length > 76 {print length}' "$HARNESS/menu.out" | head -1)
[ -z "$MW" ] && ok "menu: all lines ≤ 76 cols" || bad "menu: line ${MW} chars wide"

echo
echo "RESULT: $OK passed, $BAD failed"
[ "$BAD" -eq 0 ]
