#!/usr/bin/env python3
"""term.py -- a serial terminal for P8X that fixes the bare-LF problem.

    ./term.py [/dev/cu.usbserial-XXXX] [baud]      (defaults: auto-detect, 115200)
    Ctrl-]  quits.

Why this exists
---------------
P8X emits **bare LF** for a newline: p8cc's `puts` ends with `LDA #10` and the
firmware's PUTC writes bytes to the ACIA untranslated. Under the emulator that
looks correct only because the host tty is doing LF -> CRLF for you (ONLCR is on
by default). `screen` puts the port in raw mode and renders the bytes itself, so
nothing translates and the output staircases:

    /> dir
        18  README.TXT
                        bin/
                                bina/

This does what the tty would have: LF from the machine is shown as CRLF, and
Enter is sent as CR (which is what the monitor's and the shell's line readers
expect -- they look for $0D).

It is deliberately dependency-free (no pyserial): termios only, so it runs on a
stock Python 3 with no install and no admin rights.
"""
import os, sys, termios, tty, select, glob

BAUDS = {9600: termios.B9600, 19200: termios.B19200, 38400: termios.B38400,
         57600: termios.B57600, 115200: termios.B115200}
QUIT = 0x1D                                   # Ctrl-]

def pick_port():
    # The Tang Nano's bridge exposes two: the higher-numbered one is the console,
    # the other is the JTAG side and answers with garbage.
    ports = sorted(glob.glob("/dev/cu.usbserial-*"))
    if not ports:
        sys.exit("term.py: no /dev/cu.usbserial-* found — is the board plugged in?")
    return ports[-1]

def open_port(dev, baud):
    fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd)
    a[0] = 0                                                   # iflag: raw
    a[1] = 0                                                   # oflag: raw
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL        # cflag: 8N1
    a[3] = 0                                                   # lflag: raw
    a[4] = a[5] = BAUDS.get(baud) or sys.exit(f"unsupported baud {baud}")
    a[6] = list(a[6]); a[6][termios.VMIN] = 0; a[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, a)
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd

def main():
    args = [a for a in sys.argv[1:]]
    dev  = args[0] if args and args[0].startswith("/dev/") else pick_port()
    baud = int(args[-1]) if args and args[-1].isdigit() else 115200

    fd = open_port(dev, baud)
    print(f"P8X on {dev} at {baud}.  Ctrl-] quits.  (LF shown as CRLF)\r")

    stdin = sys.stdin.fileno()
    saved = termios.tcgetattr(stdin) if os.isatty(stdin) else None
    if saved: tty.setraw(stdin)
    try:
        while True:
            r, _, _ = select.select([fd, stdin], [], [], 0.2)
            if fd in r:
                try: data = os.read(fd, 4096)
                except BlockingIOError: data = b""
                if data:
                    # the whole point: a bare LF becomes CRLF on the way out.
                    # A CRLF the machine already sent is left alone, so the
                    # monitor (which does send CRLF) is not double-spaced.
                    out = data.replace(b"\r\n", b"\x00").replace(b"\n", b"\r\n") \
                              .replace(b"\x00", b"\r\n")
                    os.write(1, out)
            if stdin in r:
                ch = os.read(stdin, 1)
                if not ch or ch[0] == QUIT: break
                # Enter -> CR: both the monitor and the shell read $0D.
                if ch == b"\n": ch = b"\r"
                os.write(fd, ch)
    finally:
        if saved: termios.tcsetattr(stdin, termios.TCSADRAIN, saved)
        os.close(fd)
        print("\r")

if __name__ == "__main__":
    main()
