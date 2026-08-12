#!/bin/bash
# scripts/e2e/launch.sh — boot the COLDIRON ISO headless via DIRECT KERNEL BOOT.
#
# console=ttyS0 in the append spawns serial-getty so the serial E2E driver
# works (the ISO's GRUB bootappend has no console= — serial stays silent).
#
# Run as root (KVM + mounting the ISO for kernel extraction).
# Usage: launch.sh [--fresh-vault]
# Environment: E2E_DIR (workdir, default /tmp/coldiron-e2e)
set -u
E2E_DIR="${E2E_DIR:-/tmp/coldiron-e2e}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
ISO="${ISO:-$REPO/dist/coldiron-os-$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "$REPO/build.sh")-amd64.iso}"
VAULT="$E2E_DIR/vault.img"
[ -f "$ISO" ] || { echo "NO ISO: $ISO"; exit 1; }
mkdir -p "$E2E_DIR"
if [ "${1:-}" = "--fresh-vault" ]; then
  # truncate -s N on an existing N-byte file does NOT wipe LUKS headers —
  # zero the size first so the previous run's vault is really gone
  truncate -s 0 "$VAULT"
  truncate -s 256M "$VAULT"
fi
[ -f "$VAULT" ] || truncate -s 256M "$VAULT"

# Extract kernel + initrd from the ISO (once per ISO)
if [ ! -f "$E2E_DIR/vmlinuz" ] || [ ! -f "$E2E_DIR/initrd" ]; then
  mkdir -p /mnt/coldiron-iso
  mount -o loop,ro "$ISO" /mnt/coldiron-iso
  cp /mnt/coldiron-iso/live/vmlinuz-* "$E2E_DIR/vmlinuz"
  cp /mnt/coldiron-iso/live/initrd.img-* "$E2E_DIR/initrd"
  umount /mnt/coldiron-iso
fi

rm -f "$E2E_DIR/mon.sock" "$E2E_DIR/serial.sock"
setsid nohup qemu-system-x86_64 -enable-kvm -cpu host -m 4096 \
  -kernel "$E2E_DIR/vmlinuz" -initrd "$E2E_DIR/initrd" \
  -append 'boot=live config toram noswap noresume console=ttyS0 loglevel=6 ipv6.disable=1' \
  -cdrom "$ISO" -net none \
  -device qemu-xhci -device usb-storage,drive=vault \
  -drive id=vault,file="$VAULT",if=none,format=raw \
  -display none \
  -monitor unix:"$E2E_DIR/mon.sock",server=on,wait=off \
  -serial unix:"$E2E_DIR/serial.sock",server=on,wait=off \
  > "$E2E_DIR/qemu.log" 2>&1 < /dev/null &
echo "qemu pid $!"
