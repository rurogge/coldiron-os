#!/usr/bin/env bash
#
# fetch-binaries.sh — download and VERIFY third-party binaries for the ISO.
#
# Security model: this script REFUSES to stage anything unless you have
# already imported the project's signing key into keys/. Automatically
# trusting a key downloaded from the Internet would defeat the entire
# purpose of the project — verification must start from trust you
# established out-of-band (see keys/README.md).
#
# Artifacts handled here:
#   - Sparrow Wallet ${SPARROW_VERSION} — signed-manifest verification
#   - Bitcoin Core CLI tools ${BITCOIN_VERSION} — SHA256SUMS.asc GPG
#     verification against keys/bitcoin.gpg + pinned sha256 cross-check
#
# Verification flow (mirrors the official instructions for each project):
#   1. gpg --verify the detached signature on the release manifest /
#      SHA256SUMS.asc (keyrings under keys/, imported by YOU out-of-band)
#   2. recompute sha256 of the archive and compare with the verified sum
#
set -euo pipefail

cd "$(dirname "$0")/.."

SPARROW_VERSION="${SPARROW_VERSION:-2.5.3}"
SPARROW_TGZ="sparrowwallet-${SPARROW_VERSION}-x86_64.tar.gz"
SPARROW_MANIFEST="sparrow-${SPARROW_VERSION}-manifest.txt"
SPARROW_BASE_URL="https://github.com/sparrowwallet/sparrow/releases/download/${SPARROW_VERSION}"
SPARROW_TGZ_URL="${SPARROW_BASE_URL}/${SPARROW_TGZ}"
SPARROW_MANIFEST_URL="${SPARROW_BASE_URL}/${SPARROW_MANIFEST}"
SPARROW_MANIFEST_ASC_URL="${SPARROW_MANIFEST_URL}.asc"
SPARROW_KEYRING="keys/sparrow.gpg"
SPARROW_FINGERPRINT="D4D0D3202FC06849A257B38DE94618334C674B40"
SPARROW_DEST="config/includes.chroot/opt/sparrow"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

need_keyring() {
  local kr="$1" what="$2"
  if [ ! -f "${kr}" ]; then
    echo "ERROR: missing keyring ${kr} (${what})." >&2
    echo >&2
    echo "  The build refuses to verify with a key fetched on the spot." >&2
    echo "  Import the signing key(s) out-of-band, then retry. See:" >&2
    echo "    keys/README.md   (fingerprints + import commands)" >&2
    exit 1
  fi
}

# GitHub release CDN occasionally kills connections mid-flight (seen on the
# small .asc files); retry hard before giving up.
dl() {
  curl -fL --retry 8 --retry-all-errors --retry-delay 2 \
    --connect-timeout 20 -C - "$@"
}

# ---------------------------------------------------------------- Sparrow Wallet
need_keyring "${SPARROW_KEYRING}" "Sparrow Wallet signing key"

say "Downloading ${SPARROW_TGZ}"
dl "${SPARROW_TGZ_URL}" -o "${TMP}/${SPARROW_TGZ}"

say "Downloading ${SPARROW_MANIFEST} (+ .asc)"
dl "${SPARROW_MANIFEST_URL}" -o "${TMP}/${SPARROW_MANIFEST}"
dl "${SPARROW_MANIFEST_ASC_URL}" -o "${TMP}/${SPARROW_MANIFEST}.asc"

say "Verifying manifest signature with ${SPARROW_KEYRING}"
gpg --no-default-keyring --keyring "${SPARROW_KEYRING}" \
    --verify "${TMP}/${SPARROW_MANIFEST}.asc" "${TMP}/${SPARROW_MANIFEST}"

say "Cross-checking sha256 against the verified manifest"
EXPECTED="$(awk -v f="*${SPARROW_TGZ}" '$2 == f {print $1}' "${TMP}/${SPARROW_MANIFEST}")"
[ -n "${EXPECTED}" ] || { echo "ERROR: ${SPARROW_TGZ} is not listed in the manifest." >&2; exit 1; }
ACTUAL="$(sha256sum "${TMP}/${SPARROW_TGZ}" | cut -d' ' -f1)"
if [ "${ACTUAL}" != "${EXPECTED}" ]; then
  echo "ERROR: sha256 mismatch for ${SPARROW_TGZ}" >&2
  echo "  expected: ${EXPECTED}" >&2
  echo "  actual:   ${ACTUAL}" >&2
  exit 1
fi
echo "  ✔ sha256 matches manifest: ${ACTUAL:0:20}..."

say "Extracting to ${SPARROW_DEST}"
rm -rf "${SPARROW_DEST}"
mkdir -p "${SPARROW_DEST}"
tar -xzf "${TMP}/${SPARROW_TGZ}" -C "${SPARROW_DEST}" --strip-components=1
chmod 0755 "${SPARROW_DEST}/bin/Sparrow"

say "Installing desktop entry"
ICON="$(find "${SPARROW_DEST}" -maxdepth 2 -name '*.png' | head -n 1)"
[ -n "${ICON}" ] || ICON="/opt/sparrow/bin/Sparrow"
mkdir -p config/includes.chroot/usr/share/applications
cat > config/includes.chroot/usr/share/applications/sparrow.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Sparrow Wallet
Comment=Bitcoin wallet — COLDIRON OS
Exec=/opt/sparrow/bin/Sparrow
Icon=${ICON}
Terminal=false
Categories=Finance;Bitcoin;Security;
EOF

echo "  ✔ Sparrow ${SPARROW_VERSION} manifest verified and staged."

# ---------------------------------------------------------------- Bitcoin Core CLI tools
# NOT a Debian package (bitcoin-core was removed from Debian years ago).
# We stage the official bitcoincore.org binaries instead.
# Verification: SHA256SUMS.asc is GPG-verified against keys/bitcoin.gpg
# (the official release signing keys, imported by YOU out-of-band — see
# keys/README.md), AND the sha256 of the release tarball is pinned below,
# so the download must match BOTH the verified sums file AND the pinned
# hash. Two independent checks, one of them rooted in your own trust.
BITCOIN_VERSION="${BITCOIN_VERSION:-31.1}"
BITCOIN_TGZ="bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
BITCOIN_BASE_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}"
BITCOIN_TGZ_URL="${BITCOIN_BASE_URL}/${BITCOIN_TGZ}"
BITCOIN_SUMS_URL="${BITCOIN_BASE_URL}/SHA256SUMS"
BITCOIN_SUMS_ASC_URL="${BITCOIN_BASE_URL}/SHA256SUMS.asc"
BITCOIN_SHA256="b80d9c3e04da78fb6f0569685673418cf686fadba9042d926d13fb87ff503f9e"
BITCOIN_KEYRING="keys/bitcoin.gpg"
BITCOIN_DEST="config/includes.chroot/opt/bitcoin"

need_keyring "${BITCOIN_KEYRING}" "Bitcoin Core release signing keys"

say "Downloading ${BITCOIN_TGZ} (+ SHA256SUMS + SHA256SUMS.asc)"
dl "${BITCOIN_TGZ_URL}" -o "${TMP}/${BITCOIN_TGZ}"
dl "${BITCOIN_SUMS_URL}" -o "${TMP}/SHA256SUMS"
dl "${BITCOIN_SUMS_ASC_URL}" -o "${TMP}/SHA256SUMS.asc"

say "Verifying SHA256SUMS.asc signature with ${BITCOIN_KEYRING}"
# Bitcoin Core's SHA256SUMS.asc accumulates signatures from many signers
# over time; a release may be signed by a key not yet in the user keyring.
# gpg --verify then fails on that unknown signature even though every
# known key verified. The robust check: at least one GOOD signature from
# a key in OUR keyring (the out-of-band trust anchor), and no BADSIG.
if ! gpg --status-fd 1 --no-default-keyring --keyring "${BITCOIN_KEYRING}" \
       --verify "${TMP}/SHA256SUMS.asc" "${TMP}/SHA256SUMS" 2>/dev/null \
   | grep -q '^\[GNUPG:\] GOODSIG'; then
  echo "ERROR: no valid signature from a trusted Bitcoin Core key." >&2
  exit 1
fi
if gpg --status-fd 1 --no-default-keyring --keyring "${BITCOIN_KEYRING}" \
       --verify "${TMP}/SHA256SUMS.asc" "${TMP}/SHA256SUMS" 2>/dev/null \
   | grep -q '^\[GNUPG:\] BADSIG'; then
  echo "ERROR: BADSIG from a known key — the sums file is compromised." >&2
  exit 1
fi
echo "  ✔ signature valid (≥1 trusted key; no bad signatures)"

say "Verifying sha256 (pinned: ${BITCOIN_SHA256:0:16}...)"
ACTUAL="$(sha256sum "${TMP}/${BITCOIN_TGZ}" | cut -d' ' -f1)"
SUMS_ENTRY="$(awk -v f="${BITCOIN_TGZ}" '$2 == f {print $1}' "${TMP}/SHA256SUMS")"
if [ "${ACTUAL}" != "${BITCOIN_SHA256}" ] || [ "${SUMS_ENTRY}" != "${BITCOIN_SHA256}" ]; then
  echo "ERROR: sha256 mismatch for ${BITCOIN_TGZ}" >&2
  echo "  pinned:  ${BITCOIN_SHA256}" >&2
  echo "  sums:    ${SUMS_ENTRY}" >&2
  echo "  actual:  ${ACTUAL}" >&2
  exit 1
fi
echo "  ✔ sha256 matches pinned hash and GPG-verified SHA256SUMS"

say "Extracting to ${BITCOIN_DEST}"
rm -rf "${BITCOIN_DEST}"
mkdir -p "${BITCOIN_DEST}"
tar -xzf "${TMP}/${BITCOIN_TGZ}" -C "${BITCOIN_DEST}" --strip-components=1
# The appliance only needs the CLI/utility binaries; drop dev/static libs
# and docs to keep the image lean.
rm -rf "${BITCOIN_DEST}/include" "${BITCOIN_DEST}/lib" "${BITCOIN_DEST}/share"
echo "  ✔ Bitcoin Core ${BITCOIN_VERSION} staged (pinned sha256 verified)."
