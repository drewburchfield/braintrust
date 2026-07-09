#!/usr/bin/env python3
"""braintrust agy PTY wrapper.

Works around antigravity-cli#76 (agy --print only flushes to a real TTY on
some versions). On agy 1.1.0+ bare piped --print often works; this wrapper
remains the durable fallback when bare calls hang or return empty.

Usage: bt_agy_pty.py <timeout_s> agy --print "<prompt>" [flags...]
Exit:  0 = response captured | 124 = timed out | 1 = empty/other failure
"""
import fcntl
import os
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time

if len(sys.argv) < 3:
    sys.stderr.write("usage: bt_agy_pty.py <timeout_s> <cmd...>\n")
    sys.exit(2)

deadline = float(sys.argv[1])
cmd = sys.argv[2:]
master, slave = pty.openpty()
try:
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 220, 0, 0))
except Exception:
    pass

p = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)
buf = bytearray()
start = time.time()
timed_out = False

while True:
    if time.time() - start > deadline:
        p.kill()
        timed_out = True
        break
    r, _, _ = select.select([master], [], [], 1.0)
    if master in r:
        try:
            data = os.read(master, 65536)
        except OSError:
            break
        if not data:
            break
        buf += data
    if p.poll() is not None:
        try:
            while True:
                rr, _, _ = select.select([master], [], [], 0.2)
                if master not in rr:
                    break
                d = os.read(master, 65536)
                if not d:
                    break
                buf += d
        except OSError:
            pass
        break

try:
    p.wait(timeout=5)
except Exception:
    pass

raw = buf.decode("utf-8", "replace")
raw = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", raw)
raw = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", raw)
raw = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", raw).replace("\r", "")
clean = raw.strip()
sys.stderr.write(
    f"[agy-pty] rc={p.poll()} timed_out={timed_out} rawbytes={len(buf)} clean={len(clean)}\n"
)
if timed_out:
    sys.exit(124)
if not clean:
    sys.exit(1)
sys.stdout.write(clean + "\n")
sys.exit(0)
