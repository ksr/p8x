#!/usr/bin/env python3
"""bp_parts.py -- the backplane's parts as built. gen_eagle's netlist keeps the first
generation's 4-pin power header (TB4, frozen with the Eagle files); the KiCad board has
a 2-terminal Phoenix block in its place. The board (gen_backplane.py), the schematic
(sch/p8x_card.py) and the parts list (gen_bom.py) all take the backplane from here, so
none of them can disagree. GENERATORS ARE CANON."""

def as_built(bps, bpn):
    """copies of gen_eagle's bps and bpn with the power entry J11 the 2-terminal block,
    a Phoenix Contact MSTBA 2,5/2-G-5,08: terminal 1 = V+ (VCC), terminal 2 = GND"""
    bps, bpn = dict(bps), {k: list(v) for k, v in bpn.items()}
    bps["J11"] = ("PWR2",) + tuple(bps["J11"][1:])
    for net in bpn:
        bpn[net] = [(r, p) for (r, p) in bpn[net] if r != "J11"]
    bpn["VCC"].append(("J11", "1"))
    bpn["GND"].append(("J11", "2"))
    return bps, bpn
