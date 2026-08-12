#!/usr/bin/env python3
"""scripts/e2e/mon.py — QEMU monitor client. Run as root (socket is root-owned).
Usage:
  mon.py status                      VM state
  mon.py keys <key> [key...]         inject keys (sendkey): '1','ret','c','spc',...
  mon.py shot <path.ppm>             screendump
  mon.py quit
Environment: E2E_DIR (workdir, default /tmp/coldiron-e2e)
"""
import os, socket, time, sys

E2E_DIR = os.environ.get('E2E_DIR', '/tmp/coldiron-e2e')
SOCK = E2E_DIR + '/mon.sock'

def connect(tries=400, delay=0.5):
    for _ in range(tries):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(SOCK)
            s.settimeout(3.0)
            return s
        except OSError:
            time.sleep(delay)
    raise SystemExit("cannot connect to monitor")

def cmd(s, c, wait=1.2):
    s.sendall(c.encode() + b'\n')
    time.sleep(wait)
    out = b''
    try:
        while True:
            ch = s.recv(65536)
            if not ch:
                break
            out += ch
    except socket.timeout:
        pass
    return out.decode(errors='replace')

def main():
    s = connect()
    a = sys.argv[1]
    if a == 'status':
        print(cmd(s, 'info status').strip())
    elif a == 'keys':
        for k in sys.argv[2:]:
            cmd(s, f'sendkey {k}', 0.30)
    elif a == 'shot':
        cmd(s, f'screendump {sys.argv[2]}', 2.0)
        print(sys.argv[2])
    elif a == 'quit':
        cmd(s, 'quit', 0.5)
    s.close()

if __name__ == '__main__':
    main()
