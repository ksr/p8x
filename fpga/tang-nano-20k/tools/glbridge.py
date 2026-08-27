#!/usr/bin/env python3
"""glbridge.py -- the card-edge bridge protocol, host side (v1).

The reference implementation of CARD-EDGE-DESIGN.md's serial protocol:
the Mac (or anything with a serial port) drives the FPGA graphics card's
register window as if it were on the P8X bus. Used three ways:

  as a library     from glbridge import Bridge, SerialXport
  as a CLI         ./glbridge.py ping
                   ./glbridge.py rd 0x34            # GLID ('G')
                   ./glbridge.py gl "MDY 20 CLRUN 0"
                   ./glbridge.py glfile HOUSE.GL
  by the emulator  p8xemu -B forwards $FF20-$FF5F accesses through the
                   same framing (its C twin of this file)

Protocol v1 (host-driven; the card only ever replies):

  $00           PING             -> 'P' '8' 'X' 'G' <version>
  $80|idx <v>   WRITE v to reg   -> (no reply)
  $40|idx       READ reg         -> <one byte>
  $01 <n> <b..> BURST n bytes    -> $06 ACK after the last byte is
                (1-64) to GLDATA    ACCEPTED by the FIFO (flow control:
                                    at most one burst in flight)
  $02           STATUS           -> GLSTAT (fast-poll alias)

idx = I/O address - $FF20: $00-$0F the 2D device, $30-$37 the GL port.
Unknown commands are ignored by the card; the version byte behind PING
gates any v2. Dependency-free (termios only), like term.py/imgsend.py.
"""
import os, sys, glob, time, termios

# ---- register indexes (idx = I/O address - $FF20) ---------------------------
IDX_GX0    = 0x00
IDX_GCMD   = 0x05
IDX_GSTAT  = 0x06
IDX_GID0   = 0x0D
IDX_GID1   = 0x0E
IDX_GLDATA = 0x30
IDX_GLSTAT = 0x31
IDX_GLRB   = 0x32
IDX_GLERR  = 0x33
IDX_GLID   = 0x34
IDX_BRIDGEV= 0x35
IDX_BRIDGID= 0x36

CMD_PING, CMD_BURST, CMD_STATUS = 0x00, 0x01, 0x02
CMD_WR, CMD_RD = 0x80, 0x40
ACK = 0x06
MAGIC = b"P8XG"
BURST_MAX = 64


class SerialXport:
    """A byte transport over a tty, termios-raw. Opening must NOT reset
    the card (and does not: probed, never assumed -- PING is the probe)."""

    def __init__(self, dev=None, baud=115200, timeout=2.0):
        if dev is None:
            ports = sorted(glob.glob("/dev/cu.usbserial-*"))
            if not ports:
                sys.exit("glbridge: no /dev/cu.usbserial-* found -- card attached?")
            dev = ports[-1]
        self.dev = dev
        self.timeout = timeout
        self.fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        a = termios.tcgetattr(self.fd)
        a[0] = 0; a[1] = 0
        a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        a[3] = 0
        a[4] = a[5] = getattr(termios, "B%d" % baud)
        a[6] = list(a[6]); a[6][termios.VMIN] = 0; a[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, a)

    def send(self, data):
        os.write(self.fd, bytes(data))

    def recv(self, n):
        """Exactly n bytes or a timeout error -- the protocol has no
        variable-length replies, so short reads are always faults."""
        out = b""
        t0 = time.time()
        while len(out) < n:
            try:
                b = os.read(self.fd, n - len(out))
            except BlockingIOError:
                b = b""
            if b:
                out += b
            elif time.time() - t0 > self.timeout:
                raise TimeoutError("glbridge: card silent (%d of %d bytes)"
                                   % (len(out), n))
            else:
                time.sleep(0.001)
        return out

    def close(self):
        os.close(self.fd)


class Bridge:
    """Protocol v1 over any transport with send(bytes)/recv(n)."""

    def __init__(self, xport):
        self.x = xport

    def ping(self):
        """-> the card's protocol version. Raises on anything but magic."""
        self.x.send([CMD_PING])
        r = self.x.recv(5)
        if r[:4] != MAGIC:
            raise IOError("glbridge: bad PING reply %r (lcd personality? "
                          "a monitor banner means the all-in-one build)" % r)
        return r[4]

    def rdreg(self, idx):
        self.x.send([CMD_RD | (idx & 0x3F)])
        return self.x.recv(1)[0]

    def wrreg(self, idx, val):
        self.x.send([CMD_WR | (idx & 0x3F), val & 0xFF])

    def status(self):
        self.x.send([CMD_STATUS])
        return self.x.recv(1)[0]

    def burst(self, data):
        """Stream bytes to GLDATA, BURST_MAX per ack'd chunk."""
        data = bytes(data)
        i = 0
        while i < len(data):
            chunk = data[i:i + BURST_MAX]
            self.x.send(bytes([CMD_BURST, len(chunk)]) + chunk)
            r = self.x.recv(1)[0]
            if r != ACK:
                raise IOError("glbridge: burst not acked (got $%02X)" % r)
            i += len(chunk)

    # ---- conveniences over the raw ops ----------------------------------
    def gl_line(self, text):
        """One ASCII GL line, wrapped CA ... CX (the gl command's idiom)."""
        self.burst(b"CA " + text.encode("ascii") + b"\rCX ")

    def gl_file(self, path):
        """Stream a .GL scene file verbatim (it carries its own CA/CX)."""
        self.burst(open(path, "rb").read())

    def wait_idle(self, timeout=10.0):
        # GL idle AND 2D-engine idle. GLSTAT bit6 covers the interpreter
        # and walker, but the engine may still be draining its final span
        # to SDRAM when it clears (found by tb_gcard: 19 pixels short of
        # a frame) -- so poll GSTAT busy too, GCHECK's own rule.
        t0 = time.time()
        while self.status() & 0x40:
            if time.time() - t0 > timeout:
                raise TimeoutError("glbridge: GL busy did not clear")
            time.sleep(0.002)
        while self.rdreg(IDX_GSTAT) & 0x80:
            if time.time() - t0 > timeout:
                raise TimeoutError("glbridge: 2D engine busy did not clear")
            time.sleep(0.002)

    def drain_errors(self):
        errs = []
        while True:
            e = self.rdreg(IDX_GLERR)
            if e == 0:
                return errs
            errs.append(e)

    def probe(self):
        """The full identity: (GID0, GID1, GLID, BRIDGEV, BRIDGID)."""
        return tuple(self.rdreg(i) for i in
                     (IDX_GID0, IDX_GID1, IDX_GLID, IDX_BRIDGEV, IDX_BRIDGID))


def _cli():
    args = sys.argv[1:]
    dev = None
    if args and args[0].startswith("/dev/"):
        dev = args.pop(0)
    if not args:
        sys.exit(__doc__.split("\n\n")[1])
    b = Bridge(SerialXport(dev))
    op = args[0]
    if op == "ping":
        print("card protocol v%d" % b.ping())
        g0, g1, gl, bv, bi = b.probe()
        print("GID0=%02X('%c') GID1=%02X('%c') GLID=%02X('%c') "
              "BRIDGEV=%02X BRIDGID=%02X('%c')"
              % (g0, g0, g1, g1, gl, gl, bv, bi, bi))
    elif op == "rd":
        print("$%02X" % b.rdreg(int(args[1], 0)))
    elif op == "wr":
        b.wrreg(int(args[1], 0), int(args[2], 0))
    elif op == "stat":
        print("GLSTAT $%02X" % b.status())
    elif op == "gl":
        b.gl_line(" ".join(args[1:]))
        b.wait_idle()
        e = b.drain_errors()
        if e:
            print("GL errors:", e)
    elif op == "glfile":
        b.gl_file(args[1])
        b.wait_idle()
        e = b.drain_errors()
        if e:
            print("GL errors:", e)
    else:
        sys.exit("glbridge: unknown op %r" % op)


if __name__ == "__main__":
    _cli()
