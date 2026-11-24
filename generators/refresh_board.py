#!/usr/bin/env python3
"""refresh_board.py <card> ... -- bring a ROUTED board up to the generators without
routing it again: the silkscreen made again (silk_labels.py), the values, and spare
pins tied to a plane net. Run with KiCad's bundled Python, then kicad_tools.py finish.

For the boards whose .ses no longer stands for the copper: the DIN plugs of six were
moved with their tracks kept (2026-11-17, kicad_tools.py plug_edge), so REUSE_ROUTE
would bring back tracks to where the plug was.

The one electrical change it makes is a pad with no net becoming GND or VCC, which the
inner planes connect by themselves. Any other difference between the board's pads and
the generators' netlist stops it, with nothing saved: that board needs routing.
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(ROOT, "hardware", "memory-card", "kicad"))
import pcbnew
import gen_eagle as GE, gen_kicad as GK, silk_labels as SL
from bp_parts import as_built

def pad_of(dev, pin):
    if dev in ("DIN96", "DIN96C"): return pin.lower()
    return str(GE.DEV[dev]["pm"][pin]) if dev in GE.DEV else str(pin)    # (PWR2: the backplane's own)

def card(name):
    """-> (title, parts, nets) as the board's own generator has them."""
    if name == "backplane":
        bps, bpn = as_built(GE.bps, GE.bpn)
        return "P8X BACKPLANE REV C", {r: (s[0], s[1]) for r, s in bps.items()}, bpn
    if name == "memory-card":
        import mem_revf
        return (mem_revf.TITLE,) + mem_revf.revf(GE)
    t, parts, nets = GE.CARDS[name]
    return SL.card_title(t), parts, nets

def refresh(name):
    brd = os.path.join(ROOT, "hardware", name, "kicad", "p8x-%s.kicad_pcb" % name)
    title, parts, nets = card(name)
    b = pcbnew.LoadBoard(brd)
    fps = {f.GetReference(): f for f in b.GetFootprints()}
    missing = sorted(set(parts) ^ {r for r in fps if not re.match(r"H\d+$", r)})
    if missing: sys.exit("%s: parts differ from the board: %s" % (name, missing))
    want = {}
    for net, mem in nets.items():
        for ref, pin in mem:
            want[(ref, pad_of(parts[ref][0], pin))] = net
    tied, wrong = [], []
    for ref, f in fps.items():
        for p in f.Pads():
            k = (ref, p.GetNumber()); have = p.GetNetname(); w = want.get(k, "")
            if have.startswith("unconnected-"): have = ""
            if have == w: continue
            if not have and w in ("GND", "VCC"):
                p.SetNet(b.FindNet(w)); tied.append("%s.%s=%s" % (k + (w,)))
            else: wrong.append("%s.%s %r, netlist %r" % (k + (have, w)))
    if wrong: sys.exit("%s: needs routing, nothing saved: %s" % (name, wrong[:8]))
    for ref, f in fps.items():
        if ref in parts: f.SetValue(parts[ref][1])
    flat = name == "backplane"
    for t in list(b.GetDrawings()):                      # a backplane's SLOT n marks are its own
        if isinstance(t, pcbnew.PCB_TEXT) and t.GetLayer() == pcbnew.F_SilkS and not (
                flat and t.GetText().startswith("SLOT ")): b.Delete(t)
    lab = dict(parts)
    if flat: lab.update({r: ("MH", "M3") for r in fps if r not in parts})
    kw = {"angle": 0} if flat else {}
    if not SL.title_block(b, title, front=None if flat else "right", **kw): print("  SILK: no clean spot for the title block")
    fails = SL.label_board(b, lab, *GK.silk_spec(name, parts if not flat else {}), **kw)
    if tied:
        for z in b.Zones():
            if not z.GetIsRuleArea(): z.UnFill()
        pcbnew.ZONE_FILLER(b).Fill(b.Zones())
    pcbnew.SaveBoard(brd, b)
    print("refresh: %s, %d tied to a plane%s" % (name, len(tied), (" (%s)" % " ".join(tied)) if tied else ""))
    if fails: print("  SILK: no clean spot for %d: %s" % (len(fails), fails))

if __name__ == "__main__":
    for c in sys.argv[1:]: refresh(c)
    sys.stdout.flush(); os._exit(0)      # skip the wx.App event-loop exit hang (work is saved)
