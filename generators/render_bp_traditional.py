#!/usr/bin/env python3
"""Backplane traditional-style schematic PDF.

Rendered through the SAME auto-router as the cards
(render_traditional_auto.draw_card), fed a representative single-slot netlist
from gen_eagle.backplane_rep(). All 10 slots are wired in parallel, so one is
drawn.

History / why this exists: this used to be hand-drawn with per-wire coordinates.
It drifted twice — its row list fell behind the bus (missing 7 rev-C signals),
and wires were placed by eyeballed offsets that left leads floating (RIRQ was
disconnected on both ends). Driving it from the netlist fixes both by
construction: draw_card routes pin-to-pin from the net data and asserts every pin
is drawn, and the rows come from busnet() so a bus change can't silently drop a
signal. There are no hand-placed coordinates here any more.
"""
import os as _os, sys as _sys
_HERE = _os.path.dirname(_os.path.abspath(__file__)); _sys.path.insert(0, _HERE)
import gen_eagle as G
from render_traditional_auto import draw_card   # also sets reportlab invariant mode
_OUT = _os.path.join(_os.path.dirname(_HERE), "hardware", "backplane",
                     "p8x-backplane-schematic.pdf")

if __name__ == "__main__":
    title, parts, nets = G.backplane_rep()
    draw_card("backplane", title, parts, nets, _OUT)
    print("wrote", _os.path.basename(_OUT))
