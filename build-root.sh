#!/usr/bin/env bash
#
# build-root.sh — COLDIRON OS root build steps, consolidated.
#
# Run ONCE as root on the build machine:
#
#     sudo ./build-root.sh        # or from a root shell:  ./build-root.sh
#
# What it does:
#   1. installs build prerequisites (live-build, debootstrap, qemu, curl, gnupg)
#   2. imports the Sparrow Wallet signing key into keys/sparrow.gpg
#      (out-of-band trust: it PAUSES and makes you confirm the fingerprint
#       against https://sparrowwallet.com/download/ before continuing)
#   3. runs ./build.sh (fetch+verify Sparrow → live-build the ISO)
#   4. optionally smoke-tests the ISO in QEMU
#
set -euo pipefail

cd "$(dirname "$0")"

FPR="D4D0D3202FC06849A257B38DE94618334C674B40"   # Sparrow signing key
KEYRING="keys/sparrow.gpg"
ISO="dist/coldiron-os-0.1.0-amd64.iso"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run this as root (e.g. sudo ./build-root.sh)." >&2
  exit 1
fi

# ---------------------------------------------------------------- 1. prerequisites
say "1/4 Installing build prerequisites..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  live-build debootstrap debian-archive-keyring qemu-system-x86 curl gnupg

# ---------------------------------------------------------------- 2. Sparrow signing key (out-of-band trust)
if [ -f "${KEYRING}" ]; then
  say "2/4 keys/${KEYRING} already present — skipping key import."
else
  say "2/4 Importing Sparrow signing key (fingerprint ${FPR})"
  gpg --keyserver keyserver.ubuntu.com --recv-keys "${FPR}" 2>/dev/null \
    || gpg --keyserver keys.openpgp.org --recv-keys "${FPR}" 2>/dev/null \
    || { echo "ERROR: could not fetch the key from keyservers." >&2
         echo "       Obtain it manually from https://sparrowwallet.com/download/ and import it." >&2
         exit 1; }
  gpg --export "${FPR}" | gpg --no-default-keyring --keyring "${KEYRING}" --import

  echo
  echo "  The fingerprint below MUST match the one published on"
  echo "  https://sparrowwallet.com/download/  (\"Verifying the Release\"):"
  gpg --no-default-keyring --keyring "${KEYRING}" --fingerprint "${FPR}" 2>/dev/null \
    || gpg --no-default-keyring --keyring "${KEYRING}" --fingerprint
  read -r -p "  Type CONFIRM to continue, anything else to abort: " ANS
  [ "${ANS}" = "CONFIRM" ] || { echo "Aborted."; exit 1; }
fi

# ---------------------------------------------------------------- 3. build
say "3/4 Building the ISO (15-60 min, ~10 GB disk, 4 GB+ RAM)..."
./build.sh

# ---------------------------------------------------------------- 4. QEMU smoke test (optional)
if [ -f "${ISO}" ]; then
  echo
  read -r -p "4/4 Boot the ISO in QEMU now? [Y/n] " ANS
  case "${ANS}" in ""|y|Y) ./scripts/qemu-test.sh "${ISO}" ;; *) echo "Skipped. Test later with: ./scripts/qemu-test.sh ${ISO}" ;; esac
else
  echo "ISO not found at ${ISO} — build may have failed."
fi

say "Done."
