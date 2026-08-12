#!/usr/bin/env bash
#
# build.sh — COLDIRON OS one-command ISO builder.
#
# Builds the hardened offline cold-storage live ISO with live-build.
#
# Usage:
#   sudo ./build.sh          # full build (fetch + config + build)
#   sudo ./build.sh clean    # clean previous build artifacts (config kept)
#
# Requirements:
#   - Debian/Ubuntu host (tested on Debian 12+)
#   - root privileges (live-build/debootstrap requirement)
#   - ~10 GB free disk, 4 GB+ RAM
#   - Internet access on the BUILD machine only (the target ISO has none)
#
set -euo pipefail

cd "$(dirname "$0")"

VERSION="0.3.0"
DISTRIBUTION="trixie"
ARCH="amd64"
OUT="dist/coldiron-os-${VERSION}-${ARCH}.iso"

# ---------------------------------------------------------------- reproducible build
# SOURCE_DATE_EPOCH pins every timestamp in the ISO (live-build normalizes
# the binary tree against it, initramfs-tools honors it, the kernel build
# inherits it). The value is COMMITTED (source-date-epoch) — two builds
# with the same value must produce byte-identical ISOs; bump it per release.
export SOURCE_DATE_EPOCH="$(cat source-date-epoch 2>/dev/null || true)"
if [ -z "${SOURCE_DATE_EPOCH}" ]; then
  SOURCE_DATE_EPOCH="$(date +%s)"
  echo "WARNING: source-date-epoch file missing — using now (${SOURCE_DATE_EPOCH})." >&2
  echo "         Commit source-date-epoch for reproducible builds." >&2
  export SOURCE_DATE_EPOCH
fi

# The base image is pinned to a snapshot.debian.org date so the package
# set is frozen (reproducibility). Bump SNAPSHOT_DATE together with
# source-date-epoch when a release is prepared.
SNAPSHOT_DATE="${SNAPSHOT_DATE:-20260803T000000Z}"
SNAPSHOT_DEBIAN="http://snapshot.debian.org/archive/debian/${SNAPSHOT_DATE}/"
SNAPSHOT_SECURITY="http://snapshot.debian.org/archive/debian-security/${SNAPSHOT_DATE}/"

# ---------------------------------------------------------------- helpers
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo "$0" "$@"
    fi
    echo "ERROR: the build must run as root (live-build requires it)." >&2
    echo "       Re-run with: sudo ./build.sh" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------- prereqs
need_root "$@"

if ! command -v lb >/dev/null 2>&1 || ! command -v debootstrap >/dev/null 2>&1; then
  say "Installing live-build and debootstrap..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq live-build debootstrap curl
fi
# debootstrap needs a FRESH Debian archive keyring: the one bundled with
# Ubuntu hosts is too old to verify ${DISTRIBUTION}'s signing keys, so
# refresh it from Debian's own pool (checking for trixie's EDDSA key).
if ! gpg --no-default-keyring --keyring /usr/share/keyrings/debian-archive-keyring.gpg \
     --list-keys 41587F7DB8C774BCCF131416762F67A0B2C39DE4 >/dev/null 2>&1; then
  say "Refreshing debian-archive-keyring from the Debian pool (Ubuntu's is too old for ${DISTRIBUTION})..."
  DAK_DEB="$(curl -fsSL https://ftp.debian.org/debian/pool/main/d/debian-archive-keyring/ \
             | grep -oE 'debian-archive-keyring_[0-9.]+_all\.deb' | sort -V | tail -n 1)"
  curl -fsSL "https://ftp.debian.org/debian/pool/main/d/debian-archive-keyring/${DAK_DEB}" -o /tmp/dak.deb
  dpkg -i /tmp/dak.deb
  rm -f /tmp/dak.deb
fi

# ---------------------------------------------------------------- fetch + verify third-party binaries
say "Fetching and verifying third-party binaries (Sparrow Wallet)..."
./scripts/fetch-binaries.sh

# ---------------------------------------------------------------- networkless kernel
# The ISO ships a custom kernel compiled WITHOUT networking support and
# without loadable modules (see scripts/kernel/networkless.config). The
# .deb is built once and cached in dist/kernel/ (gitignored artifact, like
# the Sparrow/Bitcoin binaries); build.sh rebuilds it only when missing.
say "Ensuring networkless kernel package is present..."
KERNEL_VERSION="${KERNEL_VERSION:-6.12.101}"
KERNEL_REV="${KERNEL_REV:-1}"
LOCALVERSION="-coldiron"
KIMG="linux-image-${KERNEL_VERSION}${LOCALVERSION}_${KERNEL_VERSION}-${KERNEL_REV}${LOCALVERSION}_amd64.deb"
if [ ! -f "dist/kernel/${KIMG}" ]; then
  say "Kernel package missing — building the networkless kernel (~30-60 min)..."
  ./scripts/build-kernel.sh
fi
(cd dist/kernel && sha256sum -c SHA256SUMS --quiet 2>/dev/null) \
  || { echo "ERROR: dist/kernel/${KIMG} failed checksum verification." >&2; exit 1; }
mkdir -p config/packages
cp -f "dist/kernel/${KIMG}" config/packages/

# live-build schedules `linux-image-${LB_LINUX_FLAVOURS}` (coldiron) for
# installation via chroot/root/packages.chroot — a meta-package that does
# not exist upstream. Build a tiny local meta that depends on our custom
# kernel .deb (also in config/packages/, so apt resolves both locally).
say "Building linux-image-coldiron meta-package..."
META_T="$(mktemp -d /tmp/coldiron-meta.XXXXXX)"
mkdir -p "${META_T}/DEBIAN"
cat > "${META_T}/DEBIAN/control" <<EOF
Package: linux-image-coldiron
Version: ${KERNEL_VERSION}-${KERNEL_REV}${LOCALVERSION}
Architecture: amd64
Depends: linux-image-${KERNEL_VERSION}${LOCALVERSION}
Section: kernel
Priority: optional
Maintainer: COLDIRON Project <coldiron@localhost>
Description: COLDIRON OS networkless kernel (meta-package)
 This meta-package pulls the custom COLDIRON networkless kernel built
 from scripts/kernel/networkless.config + enable.config. It exists to
 satisfy live-build's --linux-flavours package scheduling.
EOF
dpkg-deb --build "${META_T}" "config/packages/linux-image-coldiron_${KERNEL_VERSION}-${KERNEL_REV}${LOCALVERSION}_amd64.deb" >/dev/null
rm -rf "${META_T}"

# ---------------------------------------------------------------- clean (optional)
if [ "${1:-}" = "clean" ]; then
  say "Cleaning previous build (config kept)..."
  lb clean 2>/dev/null || true
fi

# ---------------------------------------------------------------- configure
say "Configuring live-build (${DISTRIBUTION}/${ARCH})..."
# Normalize the mtimes of every file that ships in the image rootfs:
# live-build only normalizes the binary tree, not the chroot — without
# this, includes.chroot file timestamps would differ between builds.
find config/includes.chroot -exec touch -d "@${SOURCE_DATE_EPOCH}" {} + 2>/dev/null || true
lb config \
  --mode debian \
  --distribution "${DISTRIBUTION}" \
  --archive-areas "main contrib non-free-firmware" \
  --linux-flavours "coldiron" \
  --bootloader grub-pc \
  --binary-image iso-hybrid \
  --debian-installer false \
  --iso-application "COLDIRON OS" \
  --iso-volume "COLDIRON OS" \
  --iso-preparer "COLDIRON Project" \
  --iso-publisher "COLDIRON Project" \
  --memtest none \
  --firmware-binary false \
  --firmware-chroot false \
  --mirror-bootstrap "${SNAPSHOT_DEBIAN}" \
  --mirror-chroot "${SNAPSHOT_DEBIAN}" \
  --mirror-binary "${SNAPSHOT_DEBIAN}" \
  --mirror-chroot-security "${SNAPSHOT_SECURITY}" \
  --mirror-binary-security "${SNAPSHOT_SECURITY}" \
  --bootappend-live "boot=live config toram noswap noresume quiet loglevel=3 ipv6.disable=1 apparmor=1 security=apparmor" \
  --apt-indices false \
  --apt-options "-y --option Acquire::Retries=3" \
  --cache true

# lb config is idempotent: it PRESERVES values already in config/chroot.
# A stale run left LB_UNION_FILESYSTEM="aufs" (no aufs module in Debian
# kernels — boot would fail), while this live-build defaults to overlay.
# Force overlay here so the binary stage renders union=overlay.
sed -i 's/^LB_UNION_FILESYSTEM=.*/LB_UNION_FILESYSTEM="overlay"/' config/chroot
grep -q '^LB_UNION_FILESYSTEM="overlay"' config/chroot \
  || echo 'LB_UNION_FILESYSTEM="overlay"' >> config/chroot

# The stock kernel meta-package must NOT be installed — the image ships
# ONLY the custom networkless kernel from config/packages/ (its .deb is
# installed by live-build; the 9500 hook regenerates the initramfs with
# live-boot support). lb config re-creates this list on every run, so
# remove it here after every lb config. The flavour name is "coldiron"
# (see --linux-flavours above) so the grub generator's vmlinuz-*coldiron
# glob matches our custom kernel name.
rm -f config/package-lists/linux-image-coldiron.list.chroot

# live.list.chroot is generated by lb config with a sysvinit default
# (live-config-sysvinit + sysvinit-core) that CONFLICTS with trixie's
# systemd base: live-config pulls the systemd backend, sysvinit-core
# Conflicts systemd-sysv, and the whole resolution aborts. Override it
# with the systemd variant (lb config only creates the file if missing,
# so this stays in effect for subsequent runs).
cat > config/package-lists/live.list.chroot <<'EOF'
live-boot
live-config
live-config-systemd
EOF

# ---------------------------------------------------------------- build
# lb build does NOT detect config changes: if a previous build left the
# binary stage stamped "done", a new bootappend/template change would be
# silently ignored and the ISO would be stale. Force a binary-stage redo
# every time (the chroot stage stays cached). Cost: ~5-10 min.
say "Cleaning binary stage (config may have changed)..."
lb clean --binary 2>/dev/null || true

say "Building ISO (15-60 minutes, depending on the machine)..."
lb build

mkdir -p dist
mv -f "live-image-${ARCH}.hybrid.iso" "${OUT}"

say "Build complete."
echo "  ISO:       ${OUT}"
echo "  Size:      $(du -h "${OUT}" | cut -f1)"
echo "  SHA256:    $(sha256sum "${OUT}" | cut -d' ' -f1)"
echo
echo "Next steps:"
echo "  ./scripts/qemu-test.sh ${OUT}     # headless smoke test"
echo "  dd if=${OUT} of=/dev/sdX bs=4M status=progress   # write to USB"
