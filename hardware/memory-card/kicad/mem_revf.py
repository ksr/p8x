"""mem_revf.py -- the memory card's rev-F netlist (6 KB ROM decode), shared by
the board generator (gen_mem.py) and the schematic (generators/sch/p8x_card.py),
so both draw the same circuit. Plain Python, no pcbnew.

The canonical netlist is gen_eagle.py's CARDS["memory-card"] (rev E, left at
rev E on purpose: the Eagle flow is frozen). revf() applies the rev-F decode
on a copy -- three spare gates rewired, no new chips; see gen_mem.py's
docstring for the logic -- and asserts it.
"""
import copy

TITLE = "P8X MEMORY CARD REV F"

def revf(GE):
    """-> (PARTS, NETS) of the rev-F memory card, from gen_eagle module GE."""
    _title, parts, nets = GE.CARDS["memory-card"]
    PARTS = copy.deepcopy(parts); NETS = copy.deepcopy(nets)
    DEV = GE.DEV

    def _rm(net, *items): NETS[net] = [p for p in NETS[net] if p not in items]
    def _add(net, *items): NETS.setdefault(net, []).extend(items)

    # untie the spare gates we are about to use from GND
    _rm("GND", ("U9","4A"),("U9","4B"),
               ("U11","2A"),("U11","2B"),("U11","3A"),("U11","3B"))
    _add("A11", ("U9","4A")); _add("A12", ("U9","4B"))     # AND inputs
    NETS["P"]      = [("U9","4Y"),("U11","2B"),("U11","3B")]   # A11*A12
    _rm("Q", ("U7","3B")); _add("Q", ("U11","3A"))            # Q -> OR3 too
    NETS["ROMOR3"] = [("U11","1Y"),("U11","2A")]              # A13|A14|A15 (was ROM8CE)
    del NETS["ROM8CE"]
    NETS["ROMCE"]  = [("U11","2Y"),("U1","!CE"),("U8","3A")]  # 6K ROM !CE (+ ROM LED sel)
    NETS["S"]      = [("U11","3Y"),("U7","3B")]               # A13|A14|(A11*A12) -> RAM2 NAND

    # sanity: no pad assigned to two nets; only the spare U11.4Y output floats
    owner = {}
    for net, mem in NETS.items():
        for k in mem:
            assert k not in owner, "pad %s in two nets (%s,%s)" % (k, owner[k], net)
            owner[k] = net
    for u in ("U7","U8","U9","U11"):
        dev = PARTS[u][0]
        un = [pn for pn in DEV[dev]["L"]+DEV[dev]["R"] if (u,pn) not in owner]
        assert un == (["4Y"] if u == "U11" else []), "%s unexpected floats %s" % (u, un)
    return PARTS, NETS
