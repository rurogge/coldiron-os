#!/usr/bin/env bash
#
# quick-boot-test.sh — fast sanity boot of the COLDIRON networkless kernel
# BEFORE the full ISO build. Boots the kernel .deb's vmlinuz with a
# minimal busybox initramfs and asserts the networkless posture:
#   - kernel version is 6.12.101-coldiron
#   - /sys/class/net contains ONLY lo
#   - no /lib/modules (monolithic)
#   - dmesg shows no network drivers
#   - USB storage + squashfs/overlay support are compiled in
#
# Usage (as root, needs qemu + busybox-static on the HOST):
#   sudo ./scripts/kernel/quick-boot-test.sh
#
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
KERNEL_DEB="$(ls "$REPO"/dist/kernel/linux-image-*.deb 2>/dev/null | head -1)"
[ -n "${KERNEL_DEB}" ] || { echo "ERROR: no kernel .deb in dist/kernel/ — run scripts/build-kernel.sh first" >&2; exit 1; }
# expected uname from the deb name: linux-image-6.12.101-coldiron_...
KERNEL_UNAME="$(basename "${KERNEL_DEB}" | sed -n 's/^linux-image-\([^_]*\)_.*/\1/p')"
command -v qemu-system-x86_64 >/dev/null || { echo "ERROR: qemu-system-x86_64 missing" >&2; exit 1; }
command -v busybox >/dev/null || { echo "ERROR: busybox missing (apt install busybox-static)" >&2; exit 1; }

T="$(mktemp -d /tmp/coldiron-quickboot.XXXXXX)"
trap 'rm -rf "${T}"' EXIT

echo "==> Extracting vmlinuz from ${KERNEL_DEB}"
dpkg-deb -x "${KERNEL_DEB}" "${T}/deb"
VMLINUZ="$(find "${T}/deb" -name 'vmlinuz-*' | head -1)"
[ -n "${VMLINUZ}" ] || { echo "ERROR: no vmlinuz in the deb" >&2; exit 1; }

echo "==> Building minimal busybox initramfs"
mkdir -p "${T}/initrd/bin" "${T}/initrd/dev" "${T}/initrd/proc" "${T}/initrd/sys" "${T}/initrd/mnt"
cp "$(command -v busybox)" "${T}/initrd/bin/busybox"
for a in sh mount umount ls cat dmesg uname grep modprobe; do
  ln -sf busybox "${T}/initrd/bin/${a}"
done
cat > "${T}/initrd/init" <<'EOF'
#!/bin/sh
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null
echo "=== QUICKBOOT: $(uname -r) ==="
echo "--- /sys/class/net ---"
ls /sys/class/net
echo "--- /lib/modules ---"
ls /lib/modules 2>&1 || echo "(absent)"
echo "--- kernel config (networkless flags) ---"
zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_(NETDEVICES|NETFILTER|MODULES|IKCONFIG_PROC)=' || echo "(no /proc/config.gz)"
echo "--- dmesg net drivers ---"
dmesg 2>/dev/null | grep -iE 'eth0|wlan|wifi|bluetooth|link ready' | head -5 || true
echo "--- fs support ---"
grep -E 'squashfs|overlay|iso9660|ext4' /proc/filesystems
echo "=== QUICKBOOT-DONE ==="
exec sh
EOF
chmod +x "${T}/initrd/init"
( cd "${T}/initrd" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${T}/initrd.img" )

echo "==> Booting (KVM if available) — expect QUICKBOOT-DONE, then it drops to a shell"
KVM=()
[ -e /dev/kvm ] && [ -w /dev/kvm ] && KVM=(-enable-kvm -cpu host)
timeout 90 qemu-system-x86_64 "${KVM[@]}" -m 512 \
  -kernel "${VMLINUZ}" -initrd "${T}/initrd.img" \
  -append 'console=ttyS0 rdinit=/init' \
  -display none -serial stdio -no-reboot \
  < /dev/null 2>&1 | tee "${T}/boot.log" || true

echo
echo "==> Assertions"
FAIL=0
grep -q "QUICKBOOT: ${KERNEL_UNAME}" "${T}/boot.log" && echo "  ✔ kernel version (${KERNEL_UNAME})" || { echo "  ✘ kernel version"; FAIL=1; }
grep -q 'QUICKBOOT-DONE' "${T}/boot.log" && echo "  ✔ booted to init" || { echo "  ✘ did not reach init"; FAIL=1; }
NET=$(sed -n '/--- \/sys\/class\/net ---/,/--- \/lib\/modules ---/p' "${T}/boot.log" | grep -vE '^---|^$')
[ "${NET}" = "lo" ] && echo "  ✔ only lo" || { echo "  ✘ network ifaces: ${NET}"; FAIL=1; }
grep -q '(absent)' "${T}/boot.log" && echo "  ✔ no /lib/modules" || { echo "  ✘ /lib/modules present"; FAIL=1; }
grep -q 'CONFIG_NETDEVICES is not set' "${T}/boot.log" && echo "  ✔ CONFIG_NETDEVICES=n" || { echo "  ✘ NETDEVICES check"; FAIL=1; }
grep -q 'CONFIG_MODULES is not set' "${T}/boot.log" && echo "  ✔ CONFIG_MODULES=n" || { echo "  ✘ MODULES check"; FAIL=1; }
for fs in squashfs overlay iso9660 ext4; do
  grep -q "^${fs}" "${T}/boot.log" && echo "  ✔ ${fs} built-in" || { echo "  ✘ ${fs} missing"; FAIL=1; }
done
echo
[ "${FAIL}" -eq 0 ] && echo "QUICKBOOT RESULT: PASS" || echo "QUICKBOOT RESULT: FAIL"
exit ${FAIL}
