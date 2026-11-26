"""mem_revf.py -- the memory card's rev-F netlist (6 KB ROM decode), shared by
the board generator (gen_mem.py) and the schematic (generators/sch/p8x_card.py),
so both draw the same circuit. Plain Python, no pcbnew.

The canonical netlist is gen_eagle.py's CARDS["memory-card"] (rev E, left at
rev E on purpose: the Eagle flow is frozen). revf() applies the rev-F decode
on a copy -- three spare gates rewired, no new chips; see gen_mem.py's
docstring for the logic -- plus the I/O-page gating of the data-bus buffer
(2026-11-26, two more gates), and asserts it.
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

    # bus buffer off in the I/O page (fixed 2026-11-26): -BOE was AND(-RD,-MEMW)
    # alone, so on a read of $FF00-$FFFF U3 drove the undriven MD lines onto
    # D0-D7 against the I/O, CF and PS/2 cards. Now
    #   -BOE = OR(AND(-RD,-MEMW), IOPG),  IOPG = NAND(-IOPG,-IOPG)
    # using U11.4 (the last spare OR) and U7.4 (freed from the RAM2 LED driver).
    # The LED control gates U8.2/U8.3 move with -BOE; their chip selects are
    # high in the I/O page anyway, so those LEDs behave as before.
    _rm("GND", ("U11","4A"),("U11","4B"))
    NETS["-ACC"] = [("U9","1Y"),("U11","4A")]                 # AND(-RD,-MEMW)
    NETS["-BOE"] = [("U11","4Y"),("U3","!OE"),("U8","2B"),("U8","3B")]
    _rm("-RAM2CE", ("U7","4A"),("U7","4B"))
    _add("-IOPG", ("U7","4A"),("U7","4B"))
    del NETS["RAM2ON"]
    NETS["IOPG"] = [("U7","4Y"),("U11","4B")]                 # I/O page, active high
    # RAM2 LED now sinks into -RAM2CE like a plain indicator: VCC-RS5-LED7-(-RAM2CE)
    _add("VCC", ("RS5","1"))
    _rm("GND", ("LED7","K")); _add("-RAM2CE", ("LED7","K"))

    # sanity: no pad assigned to two nets; no gate pin left floating
    owner = {}
    for net, mem in NETS.items():
        for k in mem:
            assert k not in owner, "pad %s in two nets (%s,%s)" % (k, owner[k], net)
            owner[k] = net
    for u in ("U7","U8","U9","U11"):
        dev = PARTS[u][0]
        un = [pn for pn in DEV[dev]["L"]+DEV[dev]["R"] if (u,pn) not in owner]
        assert un == [], "%s unexpected floats %s" % (u, un)
    return PARTS, NETS
