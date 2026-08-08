#!/usr/bin/env bash
#
# qemu-test.sh — smoke-test the COLDIRON OS ISO in QEMU.
#
# Usage:
#   ./scripts/qemu-test.sh [iso] [vault-image]
#
# Environment:
#   RAM_MB=4096   RAM for the VM (toram boot needs 4 GB+)
#
# Headless by default (console on stdio, Ctrl-A X to quit). On a machine
# with a display, drop '-display none -serial stdio' for a GUI session.
#
set -euo pipefail

cd "$(dirname "$0")/.."

ISO="${1:-dist/coldiron-os-0.1.0-amd64.iso}"
VAULT="${2:-/tmp/coldiron-vault-test.img}"
RAM_MB="${RAM_MB:-4096}"

[ -f "${ISO}" ] || { echo "ERROR: ${ISO} not found — run ./build.sh first." >&2; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 \
  || { echo "ERROR: qemu-system-x86 not found. Install: apt install qemu-system-x86" >&2; exit 1; }

# KVM if available (much faster than TCG emulation)
KVM=()
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  KVM=(-enable-kvm -cpu host)
  echo "==> KVM acceleration enabled."
fi

# Scratch vault disk (LUKS is created on first boot inside the VM)
if [ ! -f "${VAULT}" ]; then
  echo "==> Creating scratch vault disk ${VAULT} (256 MB)"
  truncate -s 256M "${VAULT}"
fi

echo "==> Booting ${ISO} (RAM ${RAM_MB} MB, network disabled)"
echo "    Ctrl-A X  → quit QEMU"
exec qemu-system-x86_64 "${KVM[@]}" \
  -m "${RAM_MB}" \
  -cdrom "${ISO}" \
  -boot d \
  -net none \
  -device qemu-xhci \
  -device usb-storage,drive=vault \
  -drive id=vault,file="${VAULT}",if=none,format=raw \
  -display none -serial stdio
