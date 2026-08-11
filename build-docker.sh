#!/usr/bin/env bash
#
# build-docker.sh — build COLDIRON OS inside a Debian trixie container.
#
# Why a container: the host (Ubuntu) ships a 2021-era live-build fork and a
# stale Debian archive keyring. Building inside debian:trixie uses trixie's
# OWN toolchain, so the build matches the target distro exactly — and it is
# reproducible on any Docker host.
#
# Usage (docker needs root):
#   sudo ./build-docker.sh
#
# After the build, smoke-test on the host:
#   ./scripts/qemu-test.sh
#
# Notes:
#   - --privileged is required: live-build mounts /proc,/sys inside the
#     build chroot (needs CAP_SYS_ADMIN/MKNOD).
#   - The repo is bind-mounted at /build; the ISO lands in dist/ on the host.
#   - keys/sparrow.gpg (your trusted keyring) is used as-is for the
#     Sparrow manifest verification — no key is downloaded by the build.
#
set -euo pipefail

cd "$(dirname "$0")"

IMG="debian:trixie"
ISO="dist/coldiron-os-0.2.0-amd64.iso"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run as root (docker needs the daemon socket): sudo ./build-docker.sh" >&2
  exit 1
fi
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 1; }
if [ ! -f keys/sparrow.gpg ]; then
  echo "ERROR: keys/sparrow.gpg missing." >&2
  echo "       Import the Sparrow signing key first (see keys/README.md, or step 2 of build-root.sh)." >&2
  exit 1
fi

echo "==> Pulling ${IMG}..."
docker pull "${IMG}" >/dev/null

echo "==> Building COLDIRON OS inside ${IMG} (15-60 min)..."
docker run --rm --privileged \
  -v "$(pwd):/build" \
  -w /build \
  -e DEBIAN_FRONTEND=noninteractive \
  "${IMG}" bash -c '
    set -euo pipefail
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq live-build debootstrap curl gnupg
    # "clean" arg = FULL lb clean (chroot + binary). REQUIRED whenever
    # config/includes.chroot content changed: lb clean --binary alone leaves
    # the chroot stage stamped "done" and the new files are silently NOT
    # baked into the ISO (v0.1.1 lesson).
    ./build.sh clean
  '

echo
echo "==> Build finished."
if [ -f "${ISO}" ]; then
  echo "    ISO:    ${ISO}  ($(du -h "${ISO}" | cut -f1))"
  echo "    SHA256: $(sha256sum "${ISO}" | cut -d' ' -f1)"
  echo "    Smoke test on the host:  ./scripts/qemu-test.sh"
else
  echo "    ISO not found at ${ISO} — the build may have failed (check the output above)."
fi
