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
#   - Sparrow Wallet ${SPARROW_VERSION} (tar.gz + detached .asc signature)
#
set -euo pipefail

cd "$(dirname "$0")/.."

SPARROW_VERSION="${SPARROW_VERSION:-2.5.2}"
SPARROW_TGZ="sparrow-${SPARROW_VERSION}-x86_64.tar.gz"
SPARROW_URL="https://github.com/sparrowwallet/sparrow/releases/download/${SPARROW_VERSION}/${SPARROW_TGZ}"
SPARROW_ASC_URL="${SPARROW_URL}.asc"
SPARROW_KEYRING="keys/sparrow.gpg"
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
    echo "    gpg --no-default-keyring --keyring ${kr} --import <signing-key.asc>" >&2
    echo "    gpg --no-default-keyring --keyring ${kr} --fingerprint   # confirm it" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------- Sparrow Wallet
need_keyring "${SPARROW_KEYRING}" "Sparrow Wallet signing key"
say "Downloading ${SPARROW_TGZ}"
curl -fL "${SPARROW_URL}" -o "${TMP}/${SPARROW_TGZ}"
curl -fL "${SPARROW_ASC_URL}" -o "${TMP}/${SPARROW_TGZ}.asc"

say "Verifying detached signature with ${SPARROW_KEYRING}"
gpg --no-default-keyring --keyring "${SPARROW_KEYRING}" \
    --verify "${TMP}/${SPARROW_TGZ}.asc" "${TMP}/${SPARROW_TGZ}"

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

echo "  ✔ Sparrow ${SPARROW_VERSION} signature verified and staged."
