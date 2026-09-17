#!/usr/bin/env python3
"""gen_sch.py -- generate the XOR trial board's KiCad SCHEMATIC from scratch.

Companion to gen_xor.py (which builds the .kicad_pcb). This builds the
matching .kicad_sch and is written to pass `kicad-cli sch erc` clean.
GENERATORS ARE CANON -- edit here and re-run; never hand-edit the .kicad_sch.

Run with SYSTEM python3 (it needs `kiutils`, a pure-Python KiCad file
library -- `pip3 install kiutils`). Unlike the PCB generator it does NOT need
KiCad's bundled python:

  python3 hardware/xor-trial/kicad/gen_sch.py

WHY WE EMIT THE S-EXPRESSION BY HAND (and only borrow symbols from kiutils):
kiutils writes the KiCad-6 file format (version 20211014). KiCad 10 will open
that, but its net/ERC engine does NOT pick up placed symbols written in the old
per-schematic `symbol_instances` style -- a netlist export comes back with zero
components, so ERC "passes" on an empty schematic (a false clean). KiCad 8+
moved the instance mapping *inside* each symbol as `(instances (project ...))`.
So we lift the full lib-symbol definitions out of the installed .kicad_sym libs
with kiutils (no geometry hand-transcribed) and emit the modern v20231120
schematic body ourselves, where every placed symbol carries its own instances
block. That is what actually registers components + nets for ERC.

Circuit (same netlist as gen_xor.py): one 74HC86 (gate 1 used; gates 2-4 have
their inputs tied to GND and outputs left no-connect), two push-buttons with 10k
pull-downs, an LED through 330R on the output, a 100nF decoupler, a 2-pin power
header. Power is drawn with +5V / GND power symbols; one PWR_FLAG on each rail
tells ERC where power enters (the board is fed from J1, not a regulator).
"""
import os, sys, re, uuid, datetime

try:
    from kiutils.symbol import SymbolLib
except ImportError:
    sys.exit("need kiutils: pip3 install kiutils")

HERE = os.path.dirname(os.path.abspath(__file__))
SYMS = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols"
OUT  = os.path.join(HERE, "xor_trial.kicad_sch")
G    = 1.27                              # KiCad connection grid (50 mil), in mm

def g(n):   return round(n * G, 2)       # grid units -> mm (keeps pins on-grid)
def U():    return str(uuid.uuid4())

# ---- lib-symbol extraction -------------------------------------------------
_cache = {}
def _lib(nick):
    if nick not in _cache:
        _cache[nick] = SymbolLib.from_file(SYMS + "/" + nick + ".kicad_sym")
    return _cache[nick]

def libsym_sexpr(nick, name):
    """A self-contained lib_symbols entry keyed by the full lib_id 'nick:name',
    lifted verbatim from the installed library.

    NOTE ON DERIVED SYMBOLS: KiCad's ERC `lib_symbol_mismatch` check re-resolves
    the library symbol and compares it byte-for-byte against the copy cached in
    the schematic. For a *derived* symbol (one written as `(extends ...)`, e.g.
    74HC86 extends 74LS86) a hand-flattened copy never reproduces KiCad's exact
    internal form and always trips the warning. So this generator refuses
    derived symbols -- place the concrete BASE symbol instead and carry the real
    part number in the instance's Value field (74HC86 and 74LS86 are the same
    symbol; U1 below is the 74LS86 body labelled "74HC86")."""
    L = _lib(nick)
    S = next((s for s in L.symbols if s.entryName == name), None)
    if S is None:
        sys.exit("symbol %s:%s not found" % (nick, name))
    if getattr(S, "extends", None):
        sys.exit("%s:%s is a derived symbol (extends %s) -- place the base "
                 "symbol and set the instance Value instead" % (nick, name, S.extends))
    txt = S.to_sexpr(indent=2)
    # the top-level symbol must be named by its full lib_id
    txt = re.sub(r'\(symbol "%s"' % re.escape(name),
                 '(symbol "%s:%s"' % (nick, name), txt, count=1)
    return txt

# ---- schematic builder -----------------------------------------------------
class Sch:
    def __init__(self, proj, paper="A4"):
        self.proj, self.paper, self.uuid = proj, paper, U()
        self.libset, self.items = {}, []

    def _uselib(self, nick, name):
        k = (nick, name)
        if k not in self.libset:
            self.libset[k] = libsym_sexpr(nick, name)
        return "%s:%s" % (nick, name)

    def _prop(self, name, val, x, y, hide=False):
        return ('    (property "%s" "%s" (at %s %s 0)\n'
                '      (effects (font (size 1.27 1.27)) (justify left)%s))'
                % (name, val, x, y, " hide" if hide else ""))

    def place(self, nick, name, ref, val, x, y, rot=0, unit=1, pins=(),
              hide_val=False, hide_ref=False, in_bom=True, ref_dx=2.54, ref_dy=-1.27):
        """Place a symbol INSTANCE. x,y are the anchor in mm (put it on-grid)."""
        libid = self._uselib(nick, name)
        su = U()
        props = [self._prop("Reference", ref, round(x + ref_dx, 2), round(y + ref_dy, 2), hide=hide_ref),
                 self._prop("Value", val, round(x + ref_dx, 2), round(y - ref_dy, 2), hide=hide_val),
                 self._prop("Footprint", "", x, y, hide=True)]
        pintxt = "".join('    (pin "%s" (uuid %s))\n' % (p, U()) for p in pins)
        self.items.append(
            '  (symbol\n'
            '    (lib_id "%s")\n'
            '    (at %s %s %d)\n'
            '    (unit %d)\n'
            '    (exclude_from_sim no) (in_bom %s) (on_board yes) (dnp no)\n'
            '    (uuid %s)\n'
            '%s\n'
            '%s'
            '    (instances\n'
            '      (project "%s"\n'
            '        (path "/%s"\n'
            '          (reference "%s") (unit %d))))\n'
            '  )'
            % (libid, x, y, rot, unit, "yes" if in_bom else "no", su,
               "\n".join(props), pintxt, self.proj, self.uuid, ref, unit))
        return su

    def wire(self, x1, y1, x2, y2):
        self.items.append('  (wire (pts (xy %s %s) (xy %s %s))\n'
                          '    (stroke (width 0) (type default)) (uuid %s))'
                          % (x1, y1, x2, y2, U()))

    def label(self, text, x, y, rot=0):
        self.items.append('  (label "%s" (at %s %s %d)\n'
                          '    (effects (font (size 1.27 1.27)) (justify left bottom)) (uuid %s))'
                          % (text, x, y, rot, U()))

    def noconnect(self, x, y):
        self.items.append('  (no_connect (at %s %s) (uuid %s))' % (x, y, U()))

    def text(self, s, x, y, size=2.0):
        self.items.append('  (text "%s" (at %s %s 0)\n'
                          '    (effects (font (size %s %s)) (justify left)) (uuid %s))'
                          % (s, x, y, size, size, U()))

    def render(self):
        libs = "\n".join(self.libset[k] for k in self.libset)
        today = datetime.date.today().isoformat()
        return ('(kicad_sch\n'
                '  (version 20231120)\n'
                '  (generator "gen_sch")\n'
                '  (generator_version "8.0")\n'
                '  (uuid "%s")\n'
                '  (paper "%s")\n'
                '  (title_block\n'
                '    (title "XOR Trial Board")\n'
                '    (date "%s")\n'
                '    (rev "A")\n'
                '    (company "P8X")\n'
                '  )\n'
                '  (lib_symbols\n%s\n  )\n'
                '%s\n'
                '  (sheet_instances\n    (path "/" (page "1")))\n'
                ')\n' % (self.uuid, self.paper, today, libs, "\n".join(self.items)))

# ===========================================================================
# The board.  All anchors are given in GRID UNITS (multiples of 1.27 mm) so
# every pin -- pin offsets are all multiples of 1.27 -- lands on the connection
# grid and KiCad raises no off-grid warnings.  pin_sch = (anchor + off_x,
# anchor - off_y): the symbol libs use Y-up, the schematic Y-down.
# ===========================================================================
s = Sch("xor_trial")

# ---- component instances (anchor in grid units) ---------------------------
# J1 power header: pin1(+5V)=(-4,0), pin2(GND)=(-4,-2)  [Conn_01x02]
s.place("Connector_Generic", "Conn_01x02", "J1", "+5V/GND", g(24), g(72), pins=("1", "2"))
# SW1/SW2 push-buttons: pin1=(-4,0), pin2=(+4,0)
s.place("Switch", "SW_Push", "SW1", "PUSH", g(56), g(40), pins=("1", "2"))
s.place("Switch", "SW_Push", "SW2", "PUSH", g(120), g(40), pins=("1", "2"))
# R1/R2 pull-downs, R3 LED series (vertical R: pin1=(0,+3), pin2=(0,-3))
s.place("Device", "R", "R1", "10k",  g(60),  g(56), pins=("1", "2"))
s.place("Device", "R", "R2", "10k",  g(124), g(56), pins=("1", "2"))
s.place("Device", "R", "R3", "330",  g(112), g(72), pins=("1", "2"))
# LED (horizontal: pin1 K=(-3,0), pin2 A=(+3,0))
s.place("Device", "LED", "LED1", "LED", g(112), g(88), pins=("1", "2"))
# C1 decoupler (vertical)
s.place("Device", "C", "C1", "100nF", g(72), g(96), pins=("1", "2"))
# U1 74HC86 -- FIVE unit instances, all reference U1. The symbol is 74xx:74LS86
# (74HC86 is a derived, identical symbol; see libsym_sexpr) and the part number
# rides in the Value field. Units: 1 gate1 (pins 1,2->3), 5 power (7,14), 2-4 the
# spare gates. KiCad's ERC requires EVERY unit of a multi-unit part to be placed.
XOR = ("74xx", "74LS86")
s.place(*XOR, "U1", "74HC86", g(88),  g(72),  unit=1, pins=("1", "2", "3"))
s.place(*XOR, "U1", "74HC86", g(88),  g(96),  unit=5, pins=("7", "14"),
        hide_val=True, ref_dy=-13.0)               # power unit: ref/val clear of the tall body
s.place(*XOR, "U1", "74HC86", g(56),  g(116), unit=2, pins=("4", "5", "6"),  hide_val=True)
s.place(*XOR, "U1", "74HC86", g(96),  g(116), unit=3, pins=("9", "10", "8"), hide_val=True)
s.place(*XOR, "U1", "74HC86", g(136), g(116), unit=4, pins=("12", "13", "11"), hide_val=True)

# ---- power symbols: one per power pin (coincident with the pin) ------------
# Each hidden power/flag symbol needs a UNIQUE reference (#PWR01, #PWR02, ...)
# or the netlister reports annotation errors; ERC ignores it but proper
# annotation is cheap. Counters below hand out the numbers.
_pwr = [0]
_flg = [0]
def _pn():  _pwr[0] += 1; return "#PWR%02d" % _pwr[0]
def _fn():  _flg[0] += 1; return "#FLG%02d" % _flg[0]
def p5(x, y):  s.place("power", "+5V", _pn(), "+5V", x, y, in_bom=False, pins=("1",), hide_val=True, hide_ref=True)
def gnd(x, y): s.place("power", "GND", _pn(), "GND", x, y, in_bom=False, pins=("1",), hide_val=True, hide_ref=True)

# +5V pins: J1.1, SW1.1, SW2.1, U1.14, C1.1
for x, y in [(20, 72), (52, 40), (116, 40), (88, 86), (72, 93)]:
    p5(g(x), g(y))
# GND pins: J1.2, R1.2, R2.2, U1.7, C1.2, LED1.K, and the six unused-gate inputs
for x, y in [(20, 74), (60, 59), (124, 59), (88, 106), (72, 99), (109, 88),
             (50, 114), (50, 118), (90, 114), (90, 118), (130, 114), (130, 118)]:
    gnd(g(x), g(y))

# PWR_FLAGs: tell ERC where power enters (J1). One per rail is enough -- power
# symbols of a kind are globally one net, so a single flag drives the whole rail.
s.wire(g(20), g(72), g(16), g(72)); s.place("power", "PWR_FLAG", _fn(), "PWR_FLAG", g(16), g(72), in_bom=False, pins=("1",), hide_val=True, hide_ref=True)
s.wire(g(20), g(74), g(16), g(74)); s.place("power", "PWR_FLAG", _fn(), "PWR_FLAG", g(16), g(74), in_bom=False, pins=("1",), hide_val=True, hide_ref=True)

# ---- signal nets: a short stub off each pin, with a net label on the stub --
def sig(net, x, y, dx, dy):
    s.wire(g(x), g(y), g(x + dx), g(y + dy))
    s.label(net, g(x + dx), g(y + dy))

# N1A: SW1.2, R1.1(top), U1.1
sig("N1A", 60, 40,  2, 0)      # SW1.2 -> right
sig("N1A", 60, 53,  0, -2)     # R1.1  -> up
sig("N1A", 82, 70, -2, 0)      # U1.1  -> left
# N1B: SW2.2, R2.1(top), U1.2
sig("N1B", 124, 40,  2, 0)
sig("N1B", 124, 53,  0, -2)
sig("N1B", 82,  74, -2, 0)
# N1Y: U1.3, R3.1(top)
sig("N1Y", 94, 72,  2, 0)
sig("N1Y", 112, 69, 0, -2)
# NLED: R3.2(bottom), LED1.A
sig("NLED", 112, 75, 0, 2)
sig("NLED", 115, 88, 2, 0)

# ---- no-connects on the three unused gate outputs (pins 6, 8, 11) ----------
for x, y in [(62, 116), (102, 116), (142, 116)]:
    s.noconnect(g(x), g(y))

# ---- title / note ----------------------------------------------------------
s.text("XOR trial board -- 74HC86 gate 1, two buttons w/ pull-downs, LED on 1Y", g(16), g(20))

open(OUT, "w").write(s.render())
print("wrote", OUT)
print("symbols:", len([i for i in s.items if i.lstrip().startswith("(symbol")]))
