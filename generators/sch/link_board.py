#!/usr/bin/env python3
"""link_board.py CARD -- the headless equivalent of KiCad's "Update PCB from
Schematic" (F8) for the linkage only: stamp each board footprint with the matching
schematic symbol's hierarchical UUID path, so schematic<->board cross-probing works
without opening KiCad.

The schematic and board are both generated from the canonical gen_eagle netlist, so
they share reference designators, nets and footprints; only the symbol<->footprint
UUID link is missing (the board is generated independently of the schematic). This
sets footprint.path = the symbol's KIID path from the schematic netlist. It changes
footprint METADATA only -- no pads, tracks, nets or positions move, so the routed
board and its DRC are unchanged.

    PYK generators/sch/link_board.py regbank-card
"""
import os, sys, re, subprocess
import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
CLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"

def sch_paths(sch):
    """ref -> KIID path '/<sheet_uuid>/<symbol_uuid>' from the schematic netlist."""
    net = sch[:-len(".kicad_sch")] + ".link.net"
    subprocess.run([CLI, "sch", "export", "netlist", "--format", "kicadsexpr", "-o", net, sch],
                   capture_output=True)
    t = open(net).read(); os.remove(net)
    out = {}
    for c in re.split(r"\(comp\b", t)[1:]:
        rm = re.search(r'\(ref "([^"]+)"', c)
        sp = re.search(r'\(sheetpath\s*\(names "[^"]*"\)\s*\(tstamps "([^"]*)"\)', c)
        ts = re.findall(r'\(tstamps "([^"]*)"\)', c)
        if rm and sp and ts:
            out[rm.group(1)] = sp.group(1).rstrip("/") + "/" + ts[-1]
    return out

def main():
    card = sys.argv[1]
    kdir = os.path.join(ROOT, "hardware", card, "kicad")
    pcb = os.path.join(kdir, "p8x-%s.kicad_pcb" % card)
    sch = os.path.join(kdir, "p8x-%s.kicad_sch" % card)
    paths = sch_paths(sch)
    board = pcbnew.LoadBoard(pcb)
    linked = missing = 0
    for fp in board.GetFootprints():
        ref = fp.GetReference()
        if ref in paths:
            fp.SetPath(pcbnew.KIID_PATH(paths[ref]))
            linked += 1
        else:
            missing += 1
    pcbnew.SaveBoard(pcb, board)
    print("%s: linked %d footprints to schematic symbols%s"
          % (card, linked, (" (%d unmatched)" % missing) if missing else ""))

if __name__ == "__main__":
    main()
