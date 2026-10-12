#!/usr/bin/env python3
"""Adapter: present a P8X card (generators/gen_eagle.py CARDS) to the schematic
toolchain in the same shape the P32X tooling expects.

gen_eagle.CARDS[name] = (title, parts{ref:(dev,val)}, nets{net:[(ref,pin)]}).
The connectors, decoupling caps and VCC/GND rails are already in there (gen_eagle
adds them), so this wrapper only needs to expose:

  Card.name, Card.title
  Card.parts  {ref: (device, function, value)}     (function left blank)
  Card.nets   {net: [(ref, pin), ...]}
  Card.nc     {(ref, pin)}   pins on no net -> drawn as no-connect
  Card.conn   {ref}          the board-edge/bus connector(s) on this card

SIGNALS is the set of backplane bus-signal names (busnet of every connector pin).
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import gen_eagle as GE
from p8x_symlib import SYM

# backplane bus signals: the net on each DIN pin (drop spares / unused)
SIGNALS = set()
for _p in GE.ALLPINS:
    try:
        _n = GE.busnet(_p)
    except Exception:
        _n = None
    if _n:
        SIGNALS.add(_n)

CONN_DEVS = {"DIN96C", "DIN96"}     # board-edge / backplane connectors

class Card:
    def __init__(self, name, title, parts_raw, nets):
        # parts_raw values are (dev, val) on the cards and (dev, val, x, y) on the
        # backplane -- take the first two either way.
        self.name = name
        self.title = title
        self.parts = {ref: (v[0], "", v[1]) for ref, v in parts_raw.items()}
        self.nets = {n: list(m) for n, m in nets.items() if m}
        self.conn = {r for r, (d, f, v) in self.parts.items() if d in CONN_DEVS}
        placed = {rp for m in self.nets.values() for rp in m}
        self.nc = set()
        for ref, (dev, f, v) in self.parts.items():
            if dev not in SYM:
                continue
            for p in SYM[dev]["pins"]:
                if (ref, p) not in placed:
                    self.nc.add((ref, p))

    def check_devices(self):
        return sorted({d for d, f, v in self.parts.values() if d not in SYM})

def load(name):
    if name == "backplane":
        return Card("backplane", "P8X %d-SLOT BACKPLANE REV C" % GE.NSLOT, GE.bps, GE.bpn)
    title, parts, nets = GE.CARDS[name]
    return Card(name, title, parts, nets)

# boards worth a schematic (active KiCad boards; skip the deprecated led-card)
CARDS = [c for c in GE.CARDS if c != "led-card"] + ["backplane"]

if __name__ == "__main__":
    print("SIGNALS: %d bus-signal names" % len(SIGNALS))
    for name in CARDS:
        c = load(name)
        miss = c.check_devices()
        ics = sum(1 for d, f, v in c.parts.values() if False)  # placeholder
        print("  %-16s parts=%d nets=%d nc=%d conn=%s%s"
              % (name, len(c.parts), len(c.nets), len(c.nc), sorted(c.conn),
                 "  MISSING DEVICES: %s" % miss if miss else ""))
