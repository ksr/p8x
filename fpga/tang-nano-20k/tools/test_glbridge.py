#!/usr/bin/env python3
"""test_glbridge.py -- protocol v1 against a mock card, no hardware.

The mock implements the card side of CARD-EDGE-DESIGN.md byte for byte:
a 64-entry register file, a GLDATA FIFO with capacity, PING identity,
burst acks, the STATUS alias, and silence on unknown commands. The
bridge must speak to it exactly; the same test shapes later drive the
RTL bench (tb_gcard) and the real board, so a green run here pins the
HOST side of the wire contract.

    python3 test_glbridge.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glbridge import (Bridge, MAGIC, ACK, BURST_MAX,
                      IDX_GLDATA, IDX_GLSTAT, IDX_GLERR, IDX_GLID,
                      IDX_GID0, IDX_GID1, IDX_BRIDGEV, IDX_BRIDGID)

FAILS = 0
def ok(cond, what):
    global FAILS
    if not cond:
        FAILS += 1
        print("FAIL:", what)


class MockCard:
    """The card end of the wire, as the design doc specifies it."""

    def __init__(self, fifo_cap=256):
        self.reg = [0] * 64
        self.reg[IDX_GID0] = ord('P')
        self.reg[IDX_GID1] = ord('G')
        self.reg[IDX_GLID] = ord('G')
        self.reg[IDX_BRIDGEV] = 1
        self.reg[IDX_BRIDGID] = ord('B')
        self.fifo = []
        self.fifo_cap = fifo_cap
        self.rx = b""          # bytes from the host, undecoded
        self.tx = b""          # replies waiting for the host
        self.writes = []       # (idx, val) log

    # the transport interface the Bridge sees
    def send(self, data):
        self.rx += bytes(data)
        self._step()

    def recv(self, n):
        if len(self.tx) < n:
            raise TimeoutError("mock: host wanted %d, card sent %d"
                               % (n, len(self.tx)))
        out, self.tx = self.tx[:n], self.tx[n:]
        return out

    # decode complete commands from rx
    def _step(self):
        while self.rx:
            c = self.rx[0]
            if c == 0x00:                                    # PING
                self.tx += MAGIC + bytes([self.reg[IDX_BRIDGEV]])
                self.rx = self.rx[1:]
            elif c == 0x02:                                  # STATUS
                self.tx += bytes([self.reg[IDX_GLSTAT]])
                self.rx = self.rx[1:]
            elif c == 0x01:                                  # BURST
                if len(self.rx) < 2:
                    return
                n = self.rx[1]
                if len(self.rx) < 2 + n:
                    return
                self.fifo += list(self.rx[2:2 + n])
                if len(self.fifo) > self.fifo_cap:
                    raise AssertionError("mock: FIFO overrun -- host broke "
                                         "the one-burst-in-flight rule")
                self.rx = self.rx[2 + n:]
                self.tx += bytes([ACK])
            elif c & 0x80:                                   # WRITE
                if len(self.rx) < 2:
                    return
                idx, val = c & 0x3F, self.rx[1]
                self.reg[idx] = val
                self.writes.append((idx, val))
                self.rx = self.rx[2:]
            elif c & 0x40:                                   # READ
                # identity registers have CONSTANT read sides on real
                # silicon, split from their write sides (GCOLH writes
                # share $FF2D with GID0's read) -- model that split
                i = c & 0x3F
                const = {0x0D: ord('P'), 0x0E: ord('G'), 0x34: ord('G'),
                         0x35: 1, 0x36: ord('B')}
                self.tx += bytes([const.get(i, self.reg[i])])
                self.rx = self.rx[1:]
            else:                                            # unknown: ignore
                self.rx = self.rx[1:]


def main():
    m = MockCard()
    b = Bridge(m)

    ok(b.ping() == 1, "ping version")
    ok(b.probe() == (ord('P'), ord('G'), ord('G'), 1, ord('B')), "identity probe")

    b.wrreg(0x00, 0xAB)                       # GX0
    ok(b.rdreg(0x00) == 0xAB, "write/read roundtrip")
    ok(m.writes[-1] == (0x00, 0xAB), "write reached the register file")

    m.reg[IDX_GLSTAT] = 0x42
    ok(b.status() == 0x42, "STATUS aliases GLSTAT")
    ok(b.rdreg(IDX_GLSTAT) == 0x42, "GLSTAT also plain-readable")

    b.burst(b"\x01\x02\x03")                  # small burst
    ok(m.fifo == [1, 2, 3], "burst content")

    m.fifo = []
    b.burst(bytes(range(200)))                # spans multiple acks
    ok(m.fifo == list(range(200)), "200-byte stream chunked correctly")
    ok(len(m.fifo) <= 256, "never over capacity")

    m.fifo = []
    b.gl_line("MDY 20")
    ok(bytes(m.fifo) == b"CA MDY 20\rCX ", "gl_line CA/CX wrapping")

    # unknown command from a confused host: the card ignores, stays in sync
    m.send([0x03])
    ok(b.rdreg(IDX_GID0) == ord('P'), "card in sync after unknown cmd")

    # error drain: queue two, expect [2,6] then empty
    seq = [2, 6, 0]
    class ErrReg(MockCard):
        pass
    m.reg[IDX_GLERR] = 0
    orig = m._step
    def step_with_err():
        # emulate the pop-on-read GLERR: serve from seq
        while m.rx:
            c = m.rx[0]
            if (c & 0xC0) == 0x40 and (c & 0x3F) == IDX_GLERR:
                m.tx += bytes([seq.pop(0) if seq else 0])
                m.rx = m.rx[1:]
            else:
                orig()
                break
    m._step = step_with_err
    ok(b.drain_errors() == [2, 6], "drain_errors pops until zero")

    if FAILS == 0:
        print("GLBRIDGE TEST: PASS (ping/identity, rd/wr, STATUS, chunked "
              "bursts + acks, CA/CX wrap, unknown-cmd sync, error drain)")
        return 0
    print("GLBRIDGE TEST: %d FAILURES" % FAILS)
    return 1


if __name__ == "__main__":
    sys.exit(main())
