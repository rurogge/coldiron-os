#!/usr/bin/env bash
#
# build-kernel.sh — build the COLDIRON networkless kernel from Debian
# trixie source, pinned to the exact version the ISO targets.
#
# What it produces (in dist/kernel/):
#   linux-image-6.12.101-coldiron_6.12.101-1coldiron_amd64.deb
#   SHA256SUMS
#
# The kernel is Debian trixie's linux 6.12.101 with the networking
# subsystem compiled out (scripts/kernel/networkless.config) and NO
# loadable modules (everything built-in). See the fragment for the
# rationale. This is the auditable core of the "networkless" claim:
#   - the source is Debian's own signed archive (apt-get download verifies
#     against the Debian archive keyring),
#   - the only modification is the committed config fragment,
#   - SOURCE_DATE_EPOCH makes the .deb reproducible.
#
# Usage (as root, anywhere — inside build-docker.sh it runs in the trixie
# container automatically when the .deb is missing):
#   sudo ./scripts/build-kernel.sh
#
# Environment:
#   KERNEL_VERSION=6.12.101  KERNEL_REV=1  — pin (must match trixie's pool)
#   SOURCE_DATE_EPOCH=<ts>   — set by build.sh for reproducible builds
#
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"   # captured BEFORE any cd into the build tree

KERNEL_VERSION="${KERNEL_VERSION:-6.12.101}"
KERNEL_REV="${KERNEL_REV:-1}"
# the Debian binary package names are "linux-source-6.12" / "linux-config-6.12"
# (6.12.101-1 is their VERSION, not part of the name)
LINUX_SOURCE_PKG="linux-source-6.12"
LINUX_CONFIG_PKG="linux-config-6.12"
LOCALVERSION="-coldiron"
PKG_VERSION="${KERNEL_VERSION}-${KERNEL_REV}${LOCALVERSION}"
OUT_DIR="$(pwd)/dist/kernel"      # absolute — the script cd's into the build tree
DEB_VERSION="${KERNEL_VERSION}-${KERNEL_REV}${LOCALVERSION}"
# image package filename produced by bindeb-pkg (LOCALVERSION is the suffix)
IMG_DEB="linux-image-${KERNEL_VERSION}${LOCALVERSION}_${DEB_VERSION}_amd64.deb"
FRAGMENT="scripts/kernel/networkless.config"
BUILD_DIR="$(mktemp -d /tmp/coldiron-kernel.XXXXXX)"
chmod 755 "${BUILD_DIR}"   # apt's _apt user needs read access for downloads
trap 'rm -rf "${BUILD_DIR}"' EXIT

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root (kernel build needs it)." >&2; exit 1; }
[ -f "${FRAGMENT}" ] || { echo "ERROR: ${FRAGMENT} missing." >&2; exit 1; }

mkdir -p "${OUT_DIR}"

# ---------------------------------------------------------------- deps
say "Installing kernel build dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  build-essential bc bison flex libssl-dev libelf-dev dwarves \
  rsync cpio kmod dpkg-dev file zstd

# ---------------------------------------------------------------- source (verified by apt)
say "Downloading ${LINUX_SOURCE_PKG}=${KERNEL_VERSION}-${KERNEL_REV} (apt-verified)..."
# download into the BUILD_DIR (not the repo root — keeps the working tree
# clean and avoids apt's _apt user permission warnings on bind mounts)
cd "${BUILD_DIR}"
apt-get download "${LINUX_SOURCE_PKG}=${KERNEL_VERSION}-${KERNEL_REV}" -qq
apt-get download "${LINUX_CONFIG_PKG}=${KERNEL_VERSION}-${KERNEL_REV}" -qq
cd "${REPO_ROOT}"

SRC_DEB="${LINUX_SOURCE_PKG}_${KERNEL_VERSION}-${KERNEL_REV}_all.deb"
CFG_DEB="${LINUX_CONFIG_PKG}_${KERNEL_VERSION}-${KERNEL_REV}_amd64.deb"
[ -f "${BUILD_DIR}/${SRC_DEB}" ] || { echo "ERROR: ${SRC_DEB} not downloaded." >&2; exit 1; }
[ -f "${BUILD_DIR}/${CFG_DEB}" ] || { echo "ERROR: ${CFG_DEB} not downloaded." >&2; exit 1; }

mkdir -p "${BUILD_DIR}/src" "${BUILD_DIR}/cfg"
dpkg-deb -x "${BUILD_DIR}/${SRC_DEB}" "${BUILD_DIR}/src"
dpkg-deb -x "${BUILD_DIR}/${CFG_DEB}" "${BUILD_DIR}/cfg"
TARBALL="$(find "${BUILD_DIR}/src" -name 'linux-source-*.tar.xz' | head -1)"
[ -n "${TARBALL}" ] || { echo "ERROR: kernel source tarball not found in ${SRC_DEB}." >&2; exit 1; }

say "Extracting kernel source ($(du -h "${TARBALL}" | cut -f1))..."
mkdir -p "${BUILD_DIR}/linux"
tar -xf "${TARBALL}" -C "${BUILD_DIR}/linux" --strip-components=1
cd "${BUILD_DIR}/linux"

# ---------------------------------------------------------------- config
# The linux-config deb ships xz-compressed per-flavour configs; the plain
# amd64 flavour is what linux-image-amd64 uses.
STOCK_CONFIG_XZ="$(find "${BUILD_DIR}/cfg" -name 'config.amd64_none_amd64.xz' | head -1)"
[ -n "${STOCK_CONFIG_XZ}" ] || { echo "ERROR: amd64 config not found in ${CFG_DEB}." >&2; exit 1; }
say "Starting from stock Debian config: ${STOCK_CONFIG_XZ}"
xz -dc "${STOCK_CONFIG_XZ}" > .config

say "Applying networkless fragment (${FRAGMENT})..."
# fragment lines: CONFIG_X=y | CONFIG_X=n | CONFIG_STR="" — applied via scripts/config
# (trailing "# comment" on a line is stripped; comment-only lines skipped)
while IFS= read -r line; do
  [ -n "${line}" ] || continue
  case "${line}" in \#*) continue ;; esac
  line="${line%%#*}"          # strip inline comment
  [ -n "${line}" ] || continue
  key="${line%%=*}"
  val="${line#*=}"
  # trim surrounding whitespace (comment-stripping leaves trailing spaces)
  key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
  val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
  [ -n "${key}" ] || continue   # whitespace-only comment continuation line
  case "${val}" in
    y) ./scripts/config --file .config --enable "${key}" ;;
    n) ./scripts/config --file .config --disable "${key}" ;;
    \"\") ./scripts/config --file .config --set-str "${key}" "" ;;
    *) echo "ERROR: unsupported fragment line: ${line}" >&2; exit 1 ;;
  esac
done < "${REPO_ROOT}/${FRAGMENT}"

# 2) with MODULES=n set, convert every remaining =m to =y (monolithic);
#    symbols that cannot be built-in are dropped by olddefconfig.
say "Converting remaining modules (=m) to built-in (=y) — monolithic build..."
sed -i 's/^\(CONFIG_[A-Z0-9_]*\)=m$/\1=y/' .config

say "Resolving config (olddefconfig)..."
make olddefconfig >/dev/null

# sanity: no =m may remain, networking must be gone
if grep -q '^CONFIG_[A-Z0-9_]*=m' .config; then
  echo "WARNING: some =m remain after olddefconfig:" >&2
  grep '^CONFIG_[A-Z0-9_]*=m' .config >&2 || true
fi
for sym in NETDEVICES NETFILTER WIRELESS CFG80211 MAC80211 BT NFC CAN FIREWIRE THUNDERBOLT MODULES; do
  if grep -q "^CONFIG_${sym}=y" .config || grep -q "^CONFIG_${sym}=m" .config; then
    echo "ERROR: CONFIG_${sym} is still enabled — networkless kernel failed." >&2
    grep "^CONFIG_${sym}" .config >&2 || true
    exit 1
  fi
done
# the loopback stack must survive
for sym in NET NET_LOOPBACK_DRIVER INET UNIX; do
  grep -q "^CONFIG_${sym}=y" .config || { echo "ERROR: CONFIG_${sym} missing (required)." >&2; exit 1; }
done
# boot-critical filesystems must be built-in (no modules exist in the image)
for sym in ISO9660_FS SQUASHFS OVERLAY_FS EXT4_FS VFAT_FS BLK_DEV_LOOP DM_CRYPT SCSI USB USB_XHCI_HCD USB_EHCI_HCD USB_STORAGE USB_HID BLK_DEV_SD; do
  grep -q "^CONFIG_${sym}=y" .config || { echo "ERROR: boot-critical CONFIG_${sym} not built-in." >&2; exit 1; }
done
echo "  ✔ config sanity checks passed (networkless, monolithic, boot-critical =y)"

# ---- build ----------------------------------------------------------------
say "Building kernel + image package (this takes 30-60 min on 8 cores)..."
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}"
JOBS="${JOBS:-$(nproc)}"   # allow CI/small machines to cap parallelism
make -j"${JOBS}" bindeb-pkg KDEB_PKGVERSION="${DEB_VERSION}" LOCALVERSION="${LOCALVERSION}"

# ---------------------------------------------------------------- output
IMG_DEB_PATH="$(find .. -maxdepth 1 -name "${IMG_DEB}" | head -1)"
if [ -z "${IMG_DEB_PATH}" ]; then
  echo "ERROR: expected ${IMG_DEB} not produced. Files in build root:" >&2
  ls -1 .. | grep -E '\.deb$' >&2 || true
  exit 1
fi
say "Installing image package into ${OUT_DIR}/"
cp "${IMG_DEB_PATH}" "${OUT_DIR}/"
( cd "${OUT_DIR}" && sha256sum "${IMG_DEB}" > SHA256SUMS )

say "Kernel build complete."
echo "  Image:  ${OUT_DIR}/${IMG_DEB}"
echo "  uname:  ${KERNEL_VERSION}${LOCALVERSION}"
echo "  SHA256: $(cut -d' ' -f1 "${OUT_DIR}/SHA256SUMS")"
echo
echo "  Next: build.sh picks this up automatically (copies to config/packages)."
