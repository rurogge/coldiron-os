#!/bin/bash
# scripts/e2e/run-all.sh — full E2E of every COLDIRON menu option in QEMU.
#
# Boot 1: menu render, opts 1/7/4/3 (abort/error paths), battery, vault prep,
#         opt 2 unlock (TIP appears), backup (TIP gone), restore, opt 6 shutdown.
# Boot 2: opt 5 Sparrow window.
#
# Run as root. Usage: run-all.sh
# Environment: E2E_DIR (workdir, default /tmp/coldiron-e2e), ISO
set -u
E2E_DIR="${E2E_DIR:-/tmp/coldiron-e2e}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
E2E="$REPO/scripts/e2e"
ISO="${ISO:-$REPO/dist/coldiron-os-$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "$REPO/build.sh")-amd64.iso}"
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
export E2E_DIR
ALL=0; FAILED=0

step() {  # step <name> <cmd...>
  local name="$1"; shift
  ALL=$((ALL+1))
  echo "===== $name ====="
  "$@" > "$E2E_DIR/last.log" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then FAILED=$((FAILED+1)); echo "  FAIL: $name (rc=$rc)"; tail -20 "$E2E_DIR/last.log"; else
    if grep -q "RESULT: .* 0 failed" "$E2E_DIR/last.log"; then echo "  OK: $name"; else
      FAILED=$((FAILED+1)); echo "  FAIL: $name (asserts failed)"; grep "FAIL:" "$E2E_DIR/last.log"; fi
  fi
}

qemu_alive() { pgrep -f 'qemu-syste[m]' >/dev/null 2>&1; }

[ -f "$ISO" ] || { echo "NO ISO — build not finished: $ISO"; exit 1; }
mkdir -p "$E2E_DIR"

# ============ BOOT 1 ============
echo ">>> BOOT 1 (fresh vault)"
bash "$E2E/launch.sh" --fresh-vault
sleep 45
step "boot: desktop menu renders"          python3 "$E2E/gui.py" wait-menu
step "opt 1: dice-seed abort path"         python3 "$E2E/gui.py" opt1-abort
step "opt 7: first-time guide"             python3 "$E2E/gui.py" opt7-guide
step "opt 4: restore with no backups"      python3 "$E2E/gui.py" opt4-nobackups
step "opt 3: backup abort path"            python3 "$E2E/gui.py" opt3-abort
step "serial: in-image battery"            python3 "$E2E/drive.py" battery
step "serial: vault prep (LUKS2+ext4)"     python3 "$E2E/drive.py" vaultprep
step "opt 2: unlock vault via menu"        python3 "$E2E/gui.py" opt2-unlock
step "serial: vault MOUNTED after opt2"    python3 "$E2E/drive.py" mnt
step "serial: backup flow (age-encrypted)" python3 "$E2E/drive.py" backup
step "serial: .age backup on disk"         python3 "$E2E/drive.py" agecount
step "serial: restore round-trip"          python3 "$E2E/drive.py" restore
step "opt 6: shutdown (vault mounted)"     bash -c "python3 '$E2E/mon.py' keys 6 ret && echo RESULT: 1 passed, 0 failed"

echo ">>> waiting for poweroff (opt 6)..."
GONE=0
for i in $(seq 1 90); do
  qemu_alive || { GONE=1; break; }
  sleep 2
done
ALL=$((ALL+1))
if [ "$GONE" -eq 1 ]; then echo "  OK: opt6 clean poweroff (qemu exited)"; else
  FAILED=$((FAILED+1)); echo "  FAIL: opt6 qemu still running after 180s"; fi

# ============ BOOT 2 ============
echo ">>> BOOT 2 (Sparrow window test, same vault)"
bash "$E2E/launch.sh"
sleep 45
step "boot2: desktop menu renders"          python3 "$E2E/gui.py" wait-menu
step "opt 5: Sparrow wallet window"        python3 "$E2E/gui.py" opt5-sparrow
python3 "$E2E/mon.py" quit
sleep 3

# ============ BOOT 3 ============
echo ">>> BOOT 3 (real GRUB path — verified boot chain)"
bash "$E2E/launch-grub.sh"
sleep 60
# GRUB boots the default entry after timeout=10; if the signature check
# failed, the desktop never appears and this step times out (FAIL).
step "grub-boot: desktop reached (verified boot passed)" python3 "$E2E/gui.py" wait-menu
python3 "$E2E/mon.py" quit
sleep 3

echo
echo "=========================================="
echo "E2E RESULT: $((ALL-FAILED))/$ALL steps passed"
[ "$FAILED" -eq 0 ]
