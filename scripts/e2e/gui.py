#!/usr/bin/env python3
"""scripts/e2e/gui.py — drive the COLDIRON desktop menu via monitor sendkey + OCR.
Run as root:  python3 scripts/e2e/gui.py <sub>
Subcommands: wait-menu | opt1-abort | opt7-guide | opt4-nobackups | opt3-abort
             | opt2-unlock | tip-check <present|absent> | opt5-sparrow
Environment: E2E_DIR (workdir, default /tmp/coldiron-e2e)
ONE persistent monitor connection (QEMU chardev serves one client at a time —
never poke the socket from outside while this runs).
Assertion strategy: hard-assert on stable states (menu reprint, TIP line,
guide text); transient error/abort lines are soft-asserted (they flash for
seconds and OCR polls every ~2s can miss them).
Exits 0 on pass, 1 on fail.
"""
import os, socket, subprocess, sys, time

E2E_DIR = os.environ.get('E2E_DIR', '/tmp/coldiron-e2e')
SOCK = E2E_DIR + '/mon.sock'
SHOT = E2E_DIR + '/screen.ppm'
PASS, FAIL = [], []

def connect(tries=200, delay=0.5):
    for _ in range(tries):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(SOCK)
            s.settimeout(4.0)
            return s
        except OSError:
            time.sleep(delay)
    raise SystemExit('cannot connect to monitor')

def mon_cmd(c, wait=1.0):
    mon.sendall(c.encode() + b'\n')
    time.sleep(wait)
    out = b''
    try:
        while True:
            ch = mon.recv(65536)
            if not ch:
                break
            out += ch
    except socket.timeout:
        pass
    return out.decode(errors='replace')

def keys(*ks, delay=0.35):
    for k in ks:
        mon_cmd(f'sendkey {k}', delay)

def ocr():
    mon_cmd(f'screendump {SHOT}', 2.0)
    ocr_py = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ocr.py')
    r = subprocess.run(['python3', ocr_py, SHOT],
                       capture_output=True, text=True)
    return r.stdout

def wait_text(substr, timeout=600, interval=2):
    deadline = time.time() + timeout
    last = ''
    while time.time() < deadline:
        t = ocr()
        last = t
        if substr in t:
            return t
        time.sleep(interval)
    raise SystemExit(f"TIMEOUT waiting for {substr!r} — last OCR: {last[-300:]!r}")

def check(name, cond, extra=''):
    (PASS if cond else FAIL).append(name)
    print(('  PASS: ' if cond else '  FAIL: ') + name + (f'  [{extra}]' if extra and not cond else ''), flush=True)

def note(name, cond, extra=''):
    """Non-gating observation (OCR-dependent checks that flash/mangle)."""
    print(('  note: ' if cond else '  MISS: ') + name + (f'  [{extra}]' if extra and not cond else ''), flush=True)

def menu_reprinted(timeout=60):
    """Wait until the menu banner is visible again (stable post-option state)."""
    try:
        wait_text('Generate seed from dice', timeout=timeout)
        return True
    except SystemExit:
        return False

def main():
    global mon
    mon = connect()
    sub = sys.argv[1]

    if sub == 'wait-menu':
        t = wait_text('Generate seed from dice', timeout=900)
        for s in ['Generate seed from dice', 'Unlock vault',
                  'Create encrypted seed backup', 'Restore encrypted seed backup',
                  'Launch Sparrow Wallet', 'Shut down securely', 'First-time guide',
                  'Exit to shell', 'New here? Start with option 1',
                  'offline Bitcoin vault']:
            check(f'menu: {s!r}', s in t)
        check('menu: no TIP yet (vault not mounted)', 'TIP:' not in t)

    elif sub == 'opt1-abort':
        keys('1', 'ret')
        wait_text('GENERATE SEED FROM DICE', timeout=60)
        t = wait_text('Do you understand and accept these risks', timeout=30)
        check('opt1: warning screen shown', 'Do you understand' in t)
        keys('n', 'ret')               # read -r needs Enter!
        t = wait_text('Generate seed from dice', timeout=90)   # menu reprint = no black screen
        check('opt1: abort returns to menu (no black screen)', 'Generate seed from dice' in t)
        check('opt1: Aborted. line shown', 'Aborted' in t)     # soft (transient)

    elif sub == 'opt7-guide':
        keys('7', 'ret')
        t = wait_text('What is a seed', timeout=60)
        check('opt7: guide renders', 'What is a seed' in t)
        keys('ret')
        check('opt7: returns to menu', menu_reprinted())

    elif sub == 'opt4-nobackups':
        keys('4', 'ret')
        ok = menu_reprinted()                                  # restore aborts fast -> menu back
        check('opt4: failure returns to menu (survival)', ok)
        hit = any(x in ocr() for x in ['No backups found', 'no LUKS device'])
        check('opt4: error text shown', hit)                   # soft

    elif sub == 'opt3-abort':
        keys('3', 'ret')
        t = wait_text('DIGITAL SEED BACKUP', timeout=60)
        check('opt3: warning shown', 'DIGITAL SEED BACKUP' in t)
        keys('n', 'ret')               # read -r needs Enter!
        t = wait_text('Generate seed from dice', timeout=90)
        check('opt3: abort returns to menu', 'Generate seed from dice' in t)
        check('opt3: Aborted. line shown', 'Aborted' in t)     # soft

    elif sub == 'opt8-check':
        keys('8', 'ret')
        t = wait_text('SYSTEM SECURITY CHECK', timeout=60)
        check('opt8: header shown', 'SYSTEM SECURITY CHECK' in t, t[-200:])
        t = wait_text('ALL CHECKS PASSED', timeout=120)
        check('opt8: all checks passed', 'ALL CHECKS PASSED' in t, t[-300:])
        keys('ret')
        check('opt8: returns to menu', menu_reprinted())

    elif sub == 'opt2-unlock':
        keys('2', 'ret')
        t = wait_text('Scanning for LUKS2 vault devices', timeout=60)
        check('opt2: preamble + scan shown', 'Scanning for LUKS2' in t)
        # passphrase prompt (echo off) — type it blind, slowly; verify by outcome
        keys('c', 'o', 'l', 'd', 'i', 'r', 'o', 'n', 'ret', delay=0.8)
        t = wait_text('Generate seed from dice', timeout=120)  # menu reprint after unlock
        check('opt2: unlock returns to menu', 'Generate seed from dice' in t)
        note('opt2: TIP visible (vault mounted, empty)',           # OCR-fragile
             'TIP: no seed backups in the vault' in t, t[-200:])

    elif sub == 'tip-check':
        want = sys.argv[2]   # present | absent
        keys('ret')          # re-render the menu (empty choice -> invalid -> reprint)
        t = wait_text('Generate seed from dice', timeout=60)
        hit = 'TIP: no seed backups in the vault' in t
        if want == 'present':
            check('tip: visible', hit)
        else:
            check('tip: gone after backup', not hit, t[-200:])

    elif sub == 'opt5-sparrow':
        keys('5', 'ret')
        t = wait_text('Sparrow', timeout=240)
        check('opt5: Sparrow window renders', 'Sparrow' in t, t[-300:])

    print(f"RESULT: {len(PASS)} passed, {len(FAIL)} failed")
    mon.close()
    sys.exit(0 if not FAIL else 1)

if __name__ == '__main__':
    main()
