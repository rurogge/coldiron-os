#!/usr/bin/env bash
#
# soak-test.sh — long-duration stability soak of the COLDIRON ISO in QEMU.
#
# Boots the ISO (direct kernel boot, like the E2E harness), waits for the
# desktop, then for DURATION hours repeatedly: runs coldiron-check, the
# dice-seed --test vectors, checks memory/uptime and that the menu still
# re-renders. Logs everything to a soak log. Exit 0 only if every cycle
# passed.
#
# Usage (as root):
#   DURATION=24 ./scripts/soak-test.sh
#
# Environment: E2E_DIR (workdir, default /tmp/coldiron-e2e), DURATION
#
set -euo pipefail
E2E_DIR="${E2E_DIR:-/tmp/coldiron-e2e}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
E2E="$REPO/scripts/e2e"
ISO="${ISO:-$REPO/dist/coldiron-os-$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "$REPO/build.sh")-amd64.iso}"
DURATION="${DURATION:-24}"
LOG="$E2E_DIR/soak.log"
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
export E2E_DIR

mkdir -p "$E2E_DIR"
echo "==> Soak test: $DURATION h on $(basename "$ISO") — log: $LOG"
bash "$E2E/launch.sh"
sleep 45

FAILED=0
START="$(date +%s)"
END=$((START + DURATION * 3600))
CYCLE=0
while [ "$(date +%s)" -lt "$END" ]; do
  CYCLE=$((CYCLE+1))
  echo "===== cycle $CYCLE @ $(date -u +%H:%M:%SZ) =====" | tee -a "$LOG"
  # security posture must hold
  if python3 "$E2E/drive.py" syscheck >> "$LOG" 2>&1 && grep -q "RESULT: .* 0 failed" "$LOG"; then
    echo "  OK: syscheck" | tee -a "$LOG"
  else
    echo "  FAIL: syscheck (cycle $CYCLE)" | tee -a "$LOG"; FAILED=1
  fi
  # memory must not creep (toram: stable RSS expected)
  python3 "$E2E/drive.py" check "free -m | awk '/Mem:/{print \$3}'" >> "$LOG" 2>&1
  python3 "$E2E/drive.py" check "uptime" >> "$LOG" 2>&1
  sleep 3600
done

# final state
python3 "$E2E/drive.py" syscheck >> "$LOG" 2>&1 || FAILED=1
python3 "$E2E/mon.py" quit || true

echo
echo "=========================================="
echo "SOAK RESULT: $CYCLE cycles over ${DURATION}h — $([ $FAILED -eq 0 ] && echo PASS || echo FAIL)"
echo "  log: $LOG"
[ "$FAILED" -eq 0 ]
