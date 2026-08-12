#!/bin/bash
# scripts/e2e/launch-grub.sh — boot the COLDIRON ISO through its REAL boot
# path (GRUB, BIOS-style cdrom) so the verified-boot chain is exercised:
# grub.cfg loads the embedded boot key and verifies kernel + initramfs
# (check_signatures=enforce) before loading them. If verification fails,
# the system does NOT reach the desktop — the E2E assertion is "boots".
#
# Run as root. Usage: launch-grub.sh
# Environment: E2E_DIR (workdir, default /tmp/coldiron-e2e)
set -u
E2E_DIR="${E2E_DIR:-/tmp/coldiron-e2e}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
ISO="${ISO:-$REPO/dist/coldiron-os-$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "$REPO/build.sh")-amd64.iso}"
VAULT="$E2E_DIR/vault.img"
[ -f "$ISO" ] || { echo "NO ISO: $ISO"; exit 1; }
mkdir -p "$E2E_DIR"
[ -f "$VAULT" ] || truncate -s 256M "$VAULT"

rm -f "$E2E_DIR/mon.sock" "$E2E_DIR/serial.sock"
setsid nohup qemu-system-x86_64 -enable-kvm -cpu host -m 4096 \
  -cdrom "$ISO" -boot d \
  -net none \
  -no-reboot \
  -device qemu-xhci -device usb-storage,drive=vault \
  -drive id=vault,file="$VAULT",if=none,format=raw \
  -display none \
  -monitor unix:"$E2E_DIR/mon.sock",server=on,wait=off \
  -serial unix:"$E2E_DIR/serial.sock",server=on,wait=off \
  > "$E2E_DIR/qemu-grub.log" 2>&1 < /dev/null &
echo "qemu pid $! (GRUB boot path)"
