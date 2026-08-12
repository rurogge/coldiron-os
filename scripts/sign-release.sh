#!/usr/bin/env bash
#
# sign-release.sh — sign the release ISO and its checksums with the
# COLDIRON project release key.
#
# Run on an AIR-GAPPED machine (the signing key must never touch a
# networked computer). Full ceremony: docs/SIGNING.md.
#
# Usage:
#   ./scripts/sign-release.sh            # signs the current VERSION's ISO
#   ./scripts/sign-release.sh <iso>      # or an explicit ISO path
#
# Produces next to the ISO:
#   SHA256SUMS       — sha256 of the ISO (the file users verify with)
#   SHA256SUMS.asc   — detached GPG signature (THE trust anchor)
#   <iso>.asc        — detached GPG signature of the ISO itself
#
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' build.sh)"
ISO="${1:-dist/coldiron-os-${VERSION}-amd64.iso}"

[ -f "${ISO}" ] || { echo "ERROR: ${ISO} not found." >&2; exit 1; }
command -v gpg >/dev/null || { echo "ERROR: gpg not installed." >&2; exit 1; }

# The release key must exist in the local keyring; refuse to auto-generate.
if ! gpg --list-secret-keys "COLDIRON OS Release" >/dev/null 2>&1; then
  echo "ERROR: no 'COLDIRON OS Release' secret key in this keyring." >&2
  echo "       Generate it offline per docs/SIGNING.md before signing." >&2
  exit 1
fi

DIST="$(dirname "${ISO}")"
NAME="$(basename "${ISO}")"

echo "==> Writing ${DIST}/SHA256SUMS"
( cd "${DIST}" && sha256sum "${NAME}" > SHA256SUMS )

echo "==> Signing SHA256SUMS (release trust anchor)..."
( cd "${DIST}" && gpg --batch --yes --armor --detach-sign SHA256SUMS )

echo "==> Signing the ISO itself..."
( cd "${DIST}" && gpg --batch --yes --armor --detach-sign "${NAME}" )

echo "==> Verifying both signatures..."
( cd "${DIST}" && gpg --verify SHA256SUMS.asc SHA256SUMS )
( cd "${DIST}" && gpg --verify "${NAME}.asc" "${NAME}" )

echo
echo "✅ Release signed:"
echo "   ${DIST}/SHA256SUMS"
echo "   ${DIST}/SHA256SUMS.asc"
echo "   ${DIST}/${NAME}.asc"
echo
echo "Next: attach all three to the GitHub release, and tag with:"
echo "   git tag -s v${VERSION} -m 'COLDIRON OS v${VERSION}'"
