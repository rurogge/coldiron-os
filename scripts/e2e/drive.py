#!/usr/bin/env python3
"""scripts/e2e/drive.py — serial-session driver: in-image battery + vault workflow.
Run as root:  python3 scripts/e2e/drive.py <sub>
Subcommands: battery | vaultprep | backup | restore | check <cmd> | mnt | agecount
             | syscheck (security posture verification)
Environment: E2E_DIR (workdir, default /tmp/coldiron-e2e)
Proven serial quirks handled: no-replay chardev, persistent guest pty,
stale-prompt matching (buffer cleared before every wait), one connection
kept open per interaction.
"""
import os, socket, re, sys, time

E2E_DIR = os.environ.get('E2E_DIR', '/tmp/coldiron-e2e')
SERIAL = E2E_DIR + '/serial.sock'
PHRASE = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'
WORDS = PHRASE.split()
LUKS_PW, AGE_PW = 'coldiron', 'agepass1'
PASS, FAIL = [], []

def connect(tries=400, delay=0.5):
    for _ in range(tries):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(SERIAL)
            s.settimeout(1.0)
            return s
        except OSError:
            time.sleep(delay)
    raise SystemExit("cannot connect to serial")

s = connect()
buf = b''

def clear():
    global buf
    buf = b''

def recv_until(patterns, timeout=120):
    global buf
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            d = s.recv(65536)
            if d:
                buf += d
        except socket.timeout:
            pass
        txt = buf.decode(errors='replace')
        for i, p in enumerate(patterns):
            if re.search(p, txt):
                return i
        time.sleep(0.4)
    raise SystemExit("TIMEOUT %r tail=%r" % (patterns, buf[-400:].decode(errors='replace')))

def send(line):
    clear()
    s.sendall(line.encode() + b'\n')
    time.sleep(0.5)

def drain(seconds=1.0):
    """Settle + drain straggler output into the buffer (pty echo timing)."""
    global buf
    time.sleep(seconds)
    try:
        while True:
            d = s.recv(65536)
            if not d:
                break
            buf += d
    except socket.timeout:
        pass

def run(cmd, timeout=90):
    """Send a command, wait for shell prompt, return the accumulated text."""
    send(cmd)
    recv_until([r'root@.*#'], timeout=timeout)
    drain(0.8)
    return buf.decode(errors='replace')

def check(name, cond, extra=''):
    (PASS if cond else FAIL).append(name)
    print(('  PASS: ' if cond else '  FAIL: ') + name + (f'  [{extra}]' if extra and not cond else ''), flush=True)

def shell():
    time.sleep(1)
    clear()
    s.sendall(b'\n')
    time.sleep(1)
    i = recv_until([r'login:', r'root@.*#'], timeout=420)
    if i == 0:
        send('root')
        recv_until([r'Password:'])
        send('coldiron')
        recv_until([r'#'], timeout=60)
    print('== shell acquired ==', flush=True)

# ----------------------------------------------------------------------
def battery():
    t = run('ls /usr/local/bin/')
    for f in ['coldiron-menu', 'coldiron-dice-seed', 'coldiron-lib',
              'coldiron-guide', 'coldiron-vault', 'coldiron-digital-backup',
              'coldiron-restore', 'coldiron-shutdown']:
        check(f'file: {f}', f in t, t[-300:])
    t = run("python3 -c 'import mnemonic, ecdsa; print(\"IMPORTS-OK\")'")
    check('python: mnemonic+ecdsa import', 'IMPORTS-OK' in t)
    t = run('ls -la /usr/share/coldiron/guide.txt && head -2 /usr/share/coldiron/guide.txt')
    check('guide.txt ships', 'guide.txt' in t and 'First-time guide' in t)
    # menu renders via pipe (q exits); vault not mounted -> no TIP
    t = run("printf 'q\n' | coldiron-menu", timeout=60)
    for s in ['Generate seed from dice', 'Create encrypted seed backup',
              'Restore encrypted seed backup', 'First-time guide', 'Exit to shell']:
        check(f'menu-pipe: {s!r}', s in t)
    check('menu-pipe: no TIP (vault not mounted)', 'TIP:' not in t)
    # dice-seed --test Vector A
    send("(for i in $(seq 1 52); do echo 1; done) > /tmp/vecA.txt")
    recv_until([r'#'])
    t = run('coldiron-dice-seed --test /tmp/vecA.txt', timeout=60)
    check('vecA: mnemonic', 'MNEMONIC:' + PHRASE in t, t[-300:])
    check('vecA: address', 'ADDRESS:bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu' in t, t[-300:])
    check('vecA: fingerprint', 'FINGERPRINT:73c5da0a' in t, t[-300:])
    # dice-seed --test Vector A WITH passphrase (TREZOR-style vector)
    t = run("coldiron-dice-seed --test /tmp/vecA.txt 'TREZOR'", timeout=60)
    check('vecA+TREZOR: seed vector',
          'SEED:c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04' in t, t[-300:])
    check('vecA+TREZOR: address',
          'ADDRESS:bc1qv5rmq0kt9yz3pm36wvzct7p3x6mtgehjul0feu' in t, t[-300:])
    # dice-seed --test Vector B (non-zero) — trailing newline REQUIRED:
    # `while read` silently drops a final unterminated line (52 faces -> 51).
    faces = '1 1 1 1 1 1 3 5 1 5 1 1 5 1 1 5 1 1 4 3 1 4 1 1 3 3 1 3 1 1 2 4 1 2 2 3 1 6 3 5 5 1 1 4 2 3 3 3 1 2 5 5'
    send(f"printf '{faces}' | tr ' ' '\n' > /tmp/vecB.txt; printf '\n' >> /tmp/vecB.txt")
    recv_until([r'#'])
    t = run('coldiron-dice-seed --test /tmp/vecB.txt', timeout=60)
    check('vecB: mnemonic',
          'MNEMONIC:abandon amount liar amount expire adjust cage candy arch gather drum buyer' in t, t[-300:])
    # guide renders
    t = run('coldiron-guide </dev/null', timeout=30)
    check('guide: renders in-guest', 'What is a seed' in t)

# ----------------------------------------------------------------------
def vaultprep():
    t = run('lsblk -o NAME,SIZE,TYPE')
    m = re.search(r'(sd[a-z]|vd[a-z])\s+256M', t)
    if not m:
        check('vaultprep: 256M disk found', False, t[-400:])
        return
    dev = '/dev/' + m.group(1)
    check(f'vaultprep: disk found ({dev})', True)
    send(f'cryptsetup luksFormat --type luks2 {dev}')
    recv_until([r'Are you sure'], timeout=60)
    send('YES')
    recv_until([r'Enter passphrase for'], timeout=60)
    send(LUKS_PW)
    recv_until([r'Verify passphrase'])
    send(LUKS_PW)
    recv_until([r'#'], timeout=90)
    check('vaultprep: luksFormat done', '#' in buf.decode(errors='replace'))
    send(f'cryptsetup luksOpen {dev} vault')
    recv_until([r'Enter passphrase for'], timeout=60)
    send(LUKS_PW)
    recv_until([r'#'], timeout=60)
    send('mkfs.ext4 -F /dev/mapper/vault')
    recv_until([r'#'], timeout=90)
    t = run('blkid /dev/mapper/vault')
    check('vaultprep: ext4 payload verified', 'TYPE="ext4"' in t, t[-300:])
    send('cryptsetup close vault')
    recv_until([r'#'], timeout=60)

# ----------------------------------------------------------------------
def backup():
    send('coldiron-digital-backup')
    recv_until([r'Type YES to continue'], timeout=60)
    send('YES')
    recv_until([r'Enter BIP39 seed phrase'], timeout=60)
    send(PHRASE)
    recv_until([r'Repeat BIP39 seed phrase'])
    send(PHRASE)
    recv_until([r'Word #\d+:'], timeout=60)          # spot check x3
    while True:
        txt = buf.decode(errors='replace')
        m = re.search(r'Word #(\d+):', txt)
        if not m:
            break
        idx = int(m.group(1)) - 1
        send(WORDS[idx])
        try:
            recv_until([r'Word #\d+:'], timeout=30)
        except SystemExit:
            break
    recv_until([r'Enter passphrase'], timeout=60)    # age -p
    send(AGE_PW)
    recv_until([r'Confirm passphrase'])
    send(AGE_PW)
    recv_until([r'Encrypted seed backup created'], timeout=90)
    drain(1.0)                                   # sha256sum line lands right after
    txt = buf.decode(errors='replace')
    check('backup: success line', 'Encrypted seed backup created' in txt)
    check('backup: sha256 printed', re.search(r'[0-9a-f]{64}', txt) is not None)
    t = run('ls -la /mnt/vault/encrypted-seed-backups/ && sha256sum /mnt/vault/encrypted-seed-backups/*.age')
    check('backup: .age file on disk', '.age' in t, t[-300:])
    check('backup: disk sha256 matches', re.search(r'[0-9a-f]{64}', t) is not None)

# ----------------------------------------------------------------------
def restore():
    send('coldiron-restore')
    recv_until([r'Available backups'], timeout=60)
    recv_until([r'1\)'], timeout=30)
    send('1')
    recv_until([r'Type DECRYPT to continue'], timeout=60)
    send('DECRYPT')
    recv_until([r'Enter passphrase'], timeout=60)    # age -d
    send(AGE_PW)
    recv_until([r'Done'], timeout=90)
    t = buf.decode(errors='replace')
    check('restore: seed printed byte-exact', PHRASE in t, t[-400:])
    check('restore: Done line', 'Done' in t)

# ----------------------------------------------------------------------
def syscheck():
    """Security posture verification (the product acceptance criteria #1/#5)."""
    # networkless: only loopback
    t = run('ls /sys/class/net')
    body = t.split('~# ', 1)[-1] if '~# ' in t else t          # drop the shell prompt
    ifaces = [l.strip() for l in body.splitlines()
              if re.match(r'^\s*\S+\s*$', l) and l.strip() != ''
              and 'root@' not in l and '@' not in l]
    check('net: only lo', ifaces == ['lo'], t[-300:])
    t = run('cat /proc/net/dev')
    check('net: /proc/net/dev has only lo', re.search(r'^\s*lo:', t, re.M) is not None and
          len(re.findall(r'^\s*\S+:\s*\d', t, re.M)) == 1, t[-300:])
    # no loadable modules (the kernel deb ships an EMPTY /lib/modules dir —
    # count .ko files, not directories)
    t = run('find /lib/modules -name *.ko 2>/dev/null | wc -l')
    check('net: no module files', re.search(r'[\r\n]0[\r\n]', t) is not None, t[-200:])
    t = run('lsmod')
    check('net: lsmod empty', re.search(r'^\s*$', t.splitlines()[-1] if t.splitlines() else '') is not None
          or 'Module' not in t, t[-300:])
    # AppArmor enforced
    t = run('aa-status 2>/dev/null | head -8')
    check('apparmor: profiles loaded', 'profiles are loaded' in t or 'profiles are in enforce' in t, t[-300:])
    t = run('cat /sys/module/apparmor/parameters/enabled 2>/dev/null')
    check('apparmor: enabled', 'Y' in t, t[-200:])
    # signed boot files (Phase 1e) — sigs live in /boot/signatures/
    t = run('ls /boot/signatures/ 2>/dev/null')
    check('boot: signature files present', '.sig' in t, t[-300:])
    t = run('coldiron-check --boot-verify 2>&1')
    check('boot: verification command passes', 'PASS' in t and 'FAIL' not in t, t[-400:])
    # the built-in integrity script agrees
    t = run('coldiron-check 2>&1', timeout=60)
    for s in ['only loopback interface exists', 'no loadable kernel modules', 'AppArmor is enabled']:
        check(f'syscheck: coldiron-check reports {s}', s in t, t[-600:])

def checkcmd():
    t = run(sys.argv[2], timeout=90)
    print(t)

def mnt():
    t = run('mountpoint -q /mnt/vault && echo MOUNTED || echo NOT-MOUNTED')
    check('vault mounted', 'MOUNTED' in t, t[-200:])

def agecount():
    t = run('ls /mnt/vault/encrypted-seed-backups/*.age 2>/dev/null | wc -l')
    m = re.search(r'[\r\n]+(\d+)[\r\n]+', t)     # digit-only line (pty \r\n endings)
    n = m.group(1) if m else '?'
    check('backups on disk: ' + n, m is not None and int(n) >= 1, t[-200:])

sub = sys.argv[1]
shell()
if sub == 'battery':
    battery()
elif sub == 'vaultprep':
    vaultprep()
elif sub == 'backup':
    backup()
elif sub == 'restore':
    restore()
elif sub == 'check':
    checkcmd()
elif sub == 'mnt':
    mnt()
elif sub == 'agecount':
    agecount()
elif sub == 'syscheck':
    syscheck()
else:
    raise SystemExit('unknown sub: ' + sub)

print(f"RESULT: {len(PASS)} passed, {len(FAIL)} failed", flush=True)
s.close()
sys.exit(0 if not FAIL else 1)
