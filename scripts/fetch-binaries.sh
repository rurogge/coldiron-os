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
#
# Verification flow (mirrors sparrowwallet.com/download → "Verifying the Release"):
#   1. gpg --verify the detached signature on the release manifest
#      (keyring: keys/sparrow.gpg, imported by YOU out-of-band)
#   2. recompute sha256 of the archive and compare with the manifest entry
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
    echo "  Import the signing key out-of-band, then:" >&2
    echo "    gpg --keyserver keyserver.ubuntu.com --recv-keys ${SPARROW_FINGERPRINT}" >&2
    echo "    gpg --export ${SPARROW_FINGERPRINT} | gpg --no-default-keyring --keyring ${kr} --import" >&2
    echo "    gpg --no-default-keyring --keyring ${kr} --fingerprint   # confirm it" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------- Sparrow Wallet
need_keyring "${SPARROW_KEYRING}" "Sparrow Wallet signing key"

say "Downloading ${SPARROW_TGZ}"
curl -fL "${SPARROW_TGZ_URL}" -o "${TMP}/${SPARROW_TGZ}"

say "Downloading ${SPARROW_MANIFEST} (+ .asc)"
curl -fL "${SPARROW_MANIFEST_URL}" -o "${TMP}/${SPARROW_MANIFEST}"
curl -fL "${SPARROW_MANIFEST_ASC_URL}" -o "${TMP}/${SPARROW_MANIFEST}.asc"

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
