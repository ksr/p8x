#!/usr/bin/env python3
"""serialmouse.py -- drive the P8X pointer from a real Microsoft serial mouse.

The P8X takes its mouse as standard xterm SGR reports on the console (lib_ptr:
ESC[?1002h/?1006h to enable, ESC[18t for size, then ESC[<b;x;y M/m events). When
p8xemu runs in a terminal, the terminal is the "mouse hardware." This shim
replaces the terminal's mouse with a vintage RS-232 mouse on a USB adapter:

  serial mouse --(USB-DB9)--> Mac tty  ==serialmouse.py==>  p8xemu console

It wraps p8xemu in a pty and multiplexes three streams:
  - keyboard (this terminal's stdin)      -> emulator stdin (pass-through)
  - emulator output                        -> this terminal (pass-through), while
        swallowing ESC[?100{0,2,3}h/l + ESC[?1006h/l (it tracks the enable state
        itself) and ANSWERING ESC[18t with a 480x272 grid (so lib_ptr's cell->
        pixel map is 1:1)
  - serial mouse (Microsoft protocol)      -> parsed to abs position + buttons,
        emitted as SGR into the emulator stdin while tracking is enabled

No P8X-side change: lib_ptr already speaks this protocol.

  tools/serialmouse.py --mouse /dev/cu.usbserial-XXXX -- p8xemu -B <card> -c img ee
  tools/serialmouse.py --selftest      # exercise the packet->SGR core, no hardware

The Microsoft serial-mouse protocol: 1200 baud, 7 data bits, no parity, 1 stop.
3-byte packets; the sync byte has bit6 (0x40) set, data bytes clear it:
  byte0 = 0 1 LB RB Y7 Y6 X7 X6      byte1 = 0 0 X5..X0      byte2 = 0 0 Y5..Y0
dx = signextend8((X7X6)<<6 | X5..X0);  +dx = right.  dy likewise; +dy = down.
Power comes off RTS+DTR (asserted here).
"""
import os, sys, termios, fcntl, struct, select, subprocess, pty, signal

# ---- panel geometry: report this as the "terminal size" so lib_ptr's ----------
# cell->pixel map (_pmapx/_pmapwy over a 480x272 window) is exactly 1:1.
COLS, ROWS = 480, 272

# ---- Microsoft serial-mouse packet -> events ---------------------------------
class MouseState:
    """Accumulates relative packets into an absolute screen position (sx right+,
    sy down+, clamped to the panel) and turns button/motion transitions into the
    SGR reports lib_ptr consumes."""
    def __init__(self):
        self.sx = COLS // 2
        self.sy = ROWS // 2
        self.lb = 0
        self.rb = 0
        self.buf = bytearray()

    def _sgr(self, b, press):
        col = self.sx + 1                    # _pmapx: mx-1 -> ptr_x = sx
        row = self.sy + 1                    # _pmapwy round-trips sy -> window-y
        return ("\033[<%d;%d;%d%s" % (b, col, row, "M" if press else "m")).encode()

    def feed(self, data):
        """Push raw serial bytes; return a list of SGR byte-strings to inject."""
        out = []
        self.buf += data
        while True:
            # resync: drop bytes until a sync byte (bit6 set) leads the buffer
            while self.buf and not (self.buf[0] & 0x40):
                del self.buf[0]
            if len(self.buf) < 3:
                break
            b0, b1, b2 = self.buf[0], self.buf[1], self.buf[2]
            # a valid packet's two data bytes must NOT have the sync bit
            if (b1 & 0x40) or (b2 & 0x40):
                del self.buf[0]              # false sync; slide on
                continue
            del self.buf[0:3]
            lb = (b0 >> 5) & 1
            rb = (b0 >> 4) & 1
            dx = ((b0 & 0x03) << 6) | (b1 & 0x3F)
            dy = (((b0 >> 2) & 0x03) << 6) | (b2 & 0x3F)
            if dx > 127: dx -= 256
            if dy > 127: dy -= 256
            self.sx = max(0, min(COLS - 1, self.sx + dx))
            self.sy = max(0, min(ROWS - 1, self.sy + dy))
            moved = (dx or dy)
            # button transitions first, then drag (motion while a button is held)
            if lb and not self.lb: out.append(self._sgr(0, True))
            if rb and not self.rb: out.append(self._sgr(2, True))
            if self.lb and not lb: out.append(self._sgr(0, False))
            if self.rb and not rb: out.append(self._sgr(2, False))
            # only LEFT-drag is a real gesture (moving icons); lib_ptr decodes
            # (b&3)==2 as right-PRESS before it checks the drag bit, so a right-
            # drag code (34) would spam spurious right-presses. Right button is
            # press/release only (the context menu).
            if moved and lb:
                out.append(self._sgr(32, True))
            self.lb, self.rb = lb, rb
        return out


# ---- emulator-output filter: swallow mouse-mode toggles, answer ESC[18t -------
class OutFilter:
    """Feeds forward everything except the mouse control sequences it must own:
    ESC[?100{0,2,3}h/l and ESC[?1006h/l are consumed (tracking state kept here);
    ESC[18t is consumed and answered. Returns (bytes_to_terminal, reply_bytes,
    tracking_now)."""
    def __init__(self):
        self.st = 0            # 0 normal, 1 saw ESC, 2 in CSI
        self.csi = bytearray()
        self.tracking = False

    def feed(self, data):
        fwd = bytearray()
        reply = bytearray()
        for c in data:
            if self.st == 0:
                if c == 0x1B: self.st = 1; self.csi = bytearray([c])
                else: fwd.append(c)
            elif self.st == 1:
                if c == ord('['): self.st = 2; self.csi.append(c)
                else: fwd += self.csi; fwd.append(c); self.st = 0
            else:  # in CSI: collect until a final byte 0x40..0x7E
                self.csi.append(c)
                if 0x40 <= c <= 0x7E:
                    self._csi(bytes(self.csi), fwd, reply)
                    self.st = 0
        return bytes(fwd), bytes(reply), self.tracking

    def _csi(self, seq, fwd, reply):
        s = seq.decode('latin1')
        body, final = s[2:-1], s[-1]
        if body.startswith('?') and final in 'hl':
            modes = body[1:].split(';')
            if any(m in ('1000', '1002', '1003') for m in modes):
                self.tracking = (final == 'h')
                return                     # swallow tracking-mode toggle
            if '1006' in modes:
                return                     # swallow SGR-encoding toggle
        if body == '18' and final == 't':
            reply += b"\033[8;%d;%dt" % (ROWS, COLS)   # answer the size query
            return
        fwd += seq                          # anything else: pass through


# ---- serial mouse tty ---------------------------------------------------------
def open_mouse(dev):
    fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd)
    a[0] = 0; a[1] = 0; a[3] = 0
    a[2] = termios.CREAD | termios.CLOCAL | termios.CS7      # 7 data bits
    a[4] = a[5] = termios.B1200
    a[6] = list(a[6]); a[6][termios.VMIN] = 0; a[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, a)
    DTR = getattr(termios, 'TIOCM_DTR', 0x002); RTS = getattr(termios, 'TIOCM_RTS', 0x004)
    SET = getattr(termios, 'TIOCMSET', 0x8004746d)
    fcntl.ioctl(fd, SET, struct.pack('I', DTR | RTS))       # power the mouse
    return fd


def run(mouse_dev, emu_argv):
    mouse = MouseState()
    ofilt = OutFilter()
    mfd = open_mouse(mouse_dev)
    pid, ptfd = pty.fork()
    if pid == 0:                                            # child: the emulator
        os.execvp(emu_argv[0], emu_argv)
        os._exit(127)
    # parent: raw-mode the real terminal so keystrokes pass byte-for-byte
    tin = sys.stdin.fileno()
    saved = termios.tcgetattr(tin)
    try:
        raw = termios.tcgetattr(tin)
        raw[3] &= ~(termios.ICANON | termios.ECHO | termios.ISIG | termios.IEXTEN)
        raw[0] &= ~(termios.IXON | termios.ICRNL | termios.INPCK | termios.ISTRIP)
        raw[6] = list(raw[6]); raw[6][termios.VMIN] = 1; raw[6][termios.VTIME] = 0
        termios.tcsetattr(tin, termios.TCSANOW, raw)
        while True:
            r, _, _ = select.select([ptfd, tin, mfd], [], [], 0.2)
            if ptfd in r:
                try: data = os.read(ptfd, 4096)
                except OSError: data = b""
                if not data: break                          # emulator exited
                fwd, reply, _ = ofilt.feed(data)
                if fwd: os.write(1, fwd)
                if reply: os.write(ptfd, reply)             # answer ESC[18t
            if tin in r:
                data = os.read(tin, 4096)
                if data: os.write(ptfd, data)               # keyboard -> emulator
            if mfd in r:
                try: data = os.read(mfd, 256)
                except OSError: data = b""
                for sgr in mouse.feed(data):
                    if ofilt.tracking:                      # gate on ESC[?1002h
                        os.write(ptfd, sgr)
    finally:
        termios.tcsetattr(tin, termios.TCSANOW, saved)
        try: os.close(mfd)
        except OSError: pass
        try: os.kill(pid, signal.SIGTERM)
        except OSError: pass


# ---- selftest: exercise the packet->SGR core with synthetic packets -----------
def selftest():
    def ms(lb, rb, dx, dy):
        b0 = 0x40 | (lb << 5) | (rb << 4) | (((dy >> 6) & 3) << 2) | ((dx >> 6) & 3)
        return bytes([b0 & 0x7F, dx & 0x3F, dy & 0x3F])
    m = MouseState()
    print("start at (%d,%d)" % (m.sx, m.sy))
    seq = [("move +10,+5 (no button)", ms(0, 0, 10, 5)),
           ("left DOWN, move +4,0", ms(1, 0, 4, 0)),
           ("left drag +6,+6",     ms(1, 0, 6, 6)),
           ("left UP",             ms(0, 0, 0, 0)),
           ("right DOWN",          ms(0, 1, 0, 0)),
           ("right UP",            ms(0, 0, 0, 0)),
           ("move up-left -20,-20",ms(0, 0, (-20) & 0xFF, (-20) & 0xFF))]
    ok = True
    for label, pkt in seq:
        out = m.feed(pkt)
        emitted = b"".join(out).decode('latin1').replace("\033", "ESC")
        print("  %-24s -> pos(%3d,%3d)  SGR: %s" % (label, m.sx, m.sy, emitted or "(none)"))
    # a no-button move must emit nothing (1002 mode); a click must carry the pos
    m2 = MouseState(); assert m2.feed(ms(0, 0, 5, 5)) == [], "free motion emitted SGR"
    down = b"".join(m2.feed(ms(1, 0, 0, 0))).decode('latin1')
    assert down.startswith("\033[<0;") and down.endswith("M"), down
    print("selftest: PASS (free-motion silent; click carries position; SGR well-formed)")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--selftest":
        selftest(); sys.exit(0)
    if len(args) >= 4 and args[0] == "--mouse" and "--" in args:
        dev = args[1]
        emu = args[args.index("--") + 1:]
        run(dev, emu)
    else:
        sys.exit("usage: serialmouse.py --mouse <tty> -- <emulator argv...>\n"
                 "       serialmouse.py --selftest")
