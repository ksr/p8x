#!/usr/bin/env python3
"""imgsend.py -- clone a P8XFS disk image onto the board's microSD over serial.

    ./imgsend.py ../../../os/run-disk.img [/dev/cu.usbserial-XXXX]

Needs no root and no card reader: the board writes its own card with CFWRITE.
This is the host half of `imgload.asm`, which the tools README previously said to
drive by hand -- poking 134 bytes in through the monitor's `E` command and then
streaming sectors is not something anyone should do twice.

    DESTRUCTIVE. It overwrites the card from LBA 0. Anything saved on it is gone.

Dependency-free (termios only), like term.py -- no pyserial to install.

What it does, in order:
  1. finds the console port (the bridge exposes two; the other is JTAG)
  2. assembles imgload.asm to $3000 if a .bin is not supplied
  3. pokes the loader in via `E 3000`, ECHO-PACED
  4. `G 3000`, then streams a 2-byte sector count and the image
  5. waits for the board's '.' after every sector, and 'K' at the end

The two pacing rules are the whole difficulty, and both are in the loader's own
header for a reason:

  - poking through `E` MUST be echo-paced. The ACIA shim holds exactly one
    received byte and the monitor blocks ~87 us echoing each character, so a
    full-rate burst silently loses bytes and you get a corrupt loader that
    crashes somewhere in the middle of the transfer.
  - a sector's 512 bytes need NO pacing (the receive loop is ~4 us a byte against
    87 us on the wire), but the ACK does: CFWRITE takes milliseconds, and
    anything sent during it is dropped. Wait for the '.'.
"""

import os, sys, glob, time, termios, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))


def pick_port():
    ports = sorted(glob.glob("/dev/cu.usbserial-*"))
    if not ports:
        sys.exit("imgsend: no /dev/cu.usbserial-* found — is the board plugged in?")
    # The bridge exposes two; the HIGHER-numbered one is the console, the other
    # is JTAG and returns garbage.
    return ports[-1]


def open_port(dev, baud=115200):
    fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd)
    a[4] = a[5] = getattr(termios, "B%d" % baud)
    a[2] = (a[2] & ~termios.CSIZE & ~termios.PARENB) | termios.CS8 \
           | termios.CREAD | termios.CLOCAL
    a[0] = a[1] = a[3] = 0                    # raw: no processing either way
    a[6][termios.VMIN] = 0
    a[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, a)
    return fd


def rd(fd, n=4096):
    try:
        return os.read(fd, n)
    except OSError:
        return b""


def drain(fd, secs=0.4):
    end, out = time.time() + secs, b""
    while time.time() < end:
        out += rd(fd)
        time.sleep(0.02)
    return out


def wait_for(fd, want, timeout=10.0, collect=False):
    """Read until one of the bytes in `want` arrives. Returns (byte, seen)."""
    end, seen = time.time() + timeout, b""
    while time.time() < end:
        c = rd(fd, 1)
        if c:
            seen += c
            if c in want:
                return c, seen
            continue
        time.sleep(0.0005)
    return None, seen


def send_echoed(fd, s, timeout=3.0):
    """Send characters one at a time, waiting for each echo. See the header."""
    for ch in s.encode():
        os.write(fd, bytes([ch]))
        end = time.time() + timeout
        while time.time() < end:
            if rd(fd, 1):
                break
            time.sleep(0.0005)
        else:
            sys.exit("imgsend: no echo for %r — is the monitor at its '*' prompt?" % chr(ch))


def poke_byte(fd, val, timeout=3.0):
    """Write one byte through `E` and wait for the NEXT address prompt.

    Counting echoes does not work here: after the second hex digit the monitor
    also emits a whole "\r\nNNNN: vv " prompt, so a reader expecting one byte
    back per byte sent drifts out of step within a few bytes and the rest of the
    loader lands as garbage. Syncing on the prompt's ':' is self-correcting.
    """
    os.write(fd, b"%02X" % val)
    end = time.time() + timeout
    seen = b""
    while time.time() < end:
        c = rd(fd, 1)
        if not c:
            time.sleep(0.0005)
            continue
        seen += c
        if c == b":":
            drain(fd, 0.02)          # let the value and trailing space arrive
            return
    sys.exit("imgsend: no prompt after poking $%02X (saw %r)" % (val, seen[-30:]))


def main():
    args = [a for a in sys.argv[1:]]
    if not args:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    img = args[0]
    dev = args[1] if len(args) > 1 else pick_port()
    if not os.path.exists(img):
        sys.exit("imgsend: no such image: %s" % img)

    data = open(img, "rb").read()
    if len(data) % 512:
        data += b"\x00" * (512 - len(data) % 512)
    nsec = len(data) // 512
    if nsec > 65535:
        sys.exit("imgsend: %d sectors exceeds the 16-bit count" % nsec)

    loader = os.path.join(HERE, "imgload.bin")
    if not os.path.exists(loader):
        loader = "/tmp/imgload.bin"
        subprocess.run([sys.executable, os.path.join(ROOT, "assembler", "p8xasm.py"),
                        os.path.join(HERE, "imgload.asm"), "-o", loader,
                        "--base", "0x3000"],
                       check=True, stdout=subprocess.DEVNULL)
    blob = open(loader, "rb").read()

    print("port   : %s" % dev)
    print("image  : %s (%d sectors, %.1f MB)" % (img, nsec, len(data) / 1048576.0))
    print("loader : %d bytes -> $3000" % len(blob))
    print()

    fd = open_port(dev)
    drain(fd, 0.5)

    # The monitor must be at its '*' prompt. A bare CR gets us one.
    os.write(fd, b"\r")
    time.sleep(0.4)
    if b"*" not in drain(fd, 0.6):
        sys.exit("imgsend: no '*' prompt — press Enter in a terminal first, or "
                 "reload the bitstream")

    # CFINIT first. Without it every CFWRITE fails -- and before imgload learned
    # to check, it acked those failures as successes and "completed" against an
    # untouched card. The monitor's I command does the init and prints the model.
    print("initialising the card (I) ...", end="", flush=True)
    send_echoed(fd, "I\r")
    ident = drain(fd, 3.0).decode("ascii", "replace")
    if "CF OK" not in ident:
        sys.exit("\nimgsend: card did not initialise: %s" % ident.strip())
    print(" %s" % ident.strip().splitlines()[-2].strip() if len(ident.strip().splitlines()) > 1
          else " ok")

    print("poking the loader in (echo-paced) ...", end="", flush=True)
    send_echoed(fd, "E 3000\r")
    drain(fd, 0.3)
    for i, byte in enumerate(blob):
        poke_byte(fd, byte)
        if i % 16 == 15:
            print(".", end="", flush=True)
    send_echoed(fd, ".")
    drain(fd, 0.3)
    print(" done")

    # Verify before running it. A loader with one wrong byte does not fail
    # cleanly -- it runs off into RAM and the first symptom is the board echoing
    # your image back at you, which is a long way from the cause.
    print("verifying ...", end="", flush=True)
    send_echoed(fd, "D 3000\r")
    dump = drain(fd, 1.5).decode("ascii", "replace")
    got = []
    for line in dump.splitlines():
        parts = line.split()
        if len(parts) > 16 and len(parts[0]) == 4:
            try:
                int(parts[0], 16)
                got += [int(x, 16) for x in parts[1:17]]
            except ValueError:
                pass
    send_echoed(fd, ".")
    drain(fd, 0.3)
    if got[:len(blob)] != list(blob):
        n = next((i for i, (a, b) in enumerate(zip(got, blob)) if a != b), len(got))
        sys.exit("\nimgsend: loader mismatch at offset %d (board $%02X, file $%02X)"
                 % (n, got[n] if n < len(got) else -1, blob[n]))
    print(" %d bytes match" % len(blob))

    print("starting it (G 3000) ...", end="", flush=True)
    send_echoed(fd, "G 3000\r")
    drain(fd, 0.3)
    print(" running")

    os.write(fd, bytes([nsec & 0xFF, (nsec >> 8) & 0xFF]))

    t0 = time.time()
    for s in range(nsec):
        os.write(fd, data[s*512:(s+1)*512])
        c, seen = wait_for(fd, b".KE", timeout=15.0)
        if c is None:
            sys.exit("\nimgsend: no ack after sector %d (saw %r)" % (s, seen[-40:]))
        if c == b"E":
            sys.exit("\nimgsend: the board reported a WRITE ERROR at sector %d. "
                     "The card is now partly written." % s)
        if s % 64 == 0 or s == nsec - 1:
            el = time.time() - t0
            rate = (s + 1) / el if el > 0 else 0
            eta = (nsec - s - 1) / rate if rate > 0 else 0
            print("\r  sector %5d/%d  %5.1f%%  %4.0f sec/s  eta %3.0fs"
                  % (s + 1, nsec, 100.0*(s+1)/nsec, rate, eta), end="", flush=True)
    print()

    c, seen = wait_for(fd, b"K", timeout=20.0)
    os.close(fd)
    if c is None:
        sys.exit("imgsend: no final 'K' (saw %r) — the card may be incomplete" % seen[-40:])
    print("done in %.0f s — the board acked every sector and finished with 'K'."
          % (time.time() - t0))
    print("Power-cycle or reset the board, then 'B' at the monitor to boot it.")


if __name__ == "__main__":
    main()
