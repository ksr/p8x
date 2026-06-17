#!/usr/bin/env python3
"""Generate a Logisim-Evolution .circ from a P8X board netlist.

PROOF OF CONCEPT — memory card only, and UNVERIFIED: I can't run Logisim here,
so please open the output in Logisim-Evolution and report what happens.

v0 goal is to validate the format + netlist mapping, NOT to simulate logic yet.
Each IC is drawn as a labelled box of pin stubs; every pin carries a Tunnel
labelled with its net name, so same-named tunnels are electrically joined
(Logisim's named-node feature) — i.e. the board's connectivity, with no
wire-routing. Once this opens cleanly we add real component behaviour
(74xx TTL library / RAM-ROM) in v1.

Run from hardware/ (imports gen_eagle, which regenerates the boards):
    cd hardware && python3 ../generators/gen_logisim.py
Writes hardware/memory-card/p8x-memory-card.circ
"""
import sys, os
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
import gen_eagle as G

GRID = 10                       # Logisim snaps to a 10px grid
parts = G.mc_parts              # ref -> (dev, value, x, y)
nets = G.mcn                    # netname -> [(ref, pin), ...]

pin2net = {}
for nn, pins in nets.items():
    for rp in pins:
        pin2net[rp] = nn

def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
             .replace('"', "&quot;"))

def loc(x, y):
    return "(%d,%d)" % (x, y)

o = ['<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
     '<project version="1.0" source="3.9.0">',
     '  <lib desc="#Wiring" name="0"/>',
     '  <lib desc="#Base" name="1"/>',
     '  <main name="memory-card"/>',
     '  <circuit name="memory-card">',
     '    <a name="circuit" val="memory-card"/>']

x0 = 100
colw = 220          # space per chip column
rowh = GRID
order = list(parts)
for ci, ref in enumerate(order):
    dev, val = parts[ref][0], parts[ref][1]
    L = G.DEV[dev]["L"]; R = G.DEV[dev]["R"]
    cx = x0 + ci * colw
    cy = 80
    # chip label
    o.append('    <comp lib="1" loc="%s" name="Text">' % loc(cx, cy - 30))
    o.append('      <a name="text" val="%s %s (%s)"/>' % (esc(ref), esc(val), esc(dev)))
    o.append('    </comp>')
    pins = [("L", p) for p in L] + [("R", p) for p in R]
    for pi, (side, pin) in enumerate(pins):
        net = pin2net.get((ref, pin))
        py = cy + pi * 3 * GRID
        # pin name as a text stub
        o.append('    <comp lib="1" loc="%s" name="Text">' % loc(cx, py))
        o.append('      <a name="text" val="%s"/>' % esc(pin))
        o.append('    </comp>')
        if net is None:
            continue
        # tunnel carrying the net (same label == connected)
        tx = cx + 90
        o.append('    <comp lib="0" loc="%s" name="Tunnel">' % loc(tx, py))
        o.append('      <a name="label" val="%s"/>' % esc(net))
        o.append('    </comp>')
o.append('  </circuit>')
o.append('</project>')

dst = os.path.join(os.path.dirname(_HERE), "hardware", "memory-card",
                   "p8x-memory-card.circ")
open(dst, "w").write("\n".join(o) + "\n")
print("wrote", dst, "(%d chips, %d nets)" % (len(parts), len(nets)))
