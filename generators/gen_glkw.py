#!/usr/bin/env python3
"""gen_glkw.py - single source of truth for the GL ASCII keyword table
(stage 10d, STAGE10-DESIGN.md).

Each verb: long form, short form (the PG-640A manual's, ch. 4), hex
opcode, BCNT (how many LEADING parameters are byte-width -- 0, 1 or 3;
every later parameter is int16 LE), ARITY (total parameter count; 15 =
variable: a POLY count byte, then count * (2 or 3) int16s by opcode
bit 1). CA/CX are mode switches handled inside the translators and get
the internal markers 0xFE/0xFF.

Emits:
  generators/glkwtab.h   (C)       -> #include'd by the emulator
  fpga/rtl/glkwtab.vh    (Verilog) -> `include'd inside p8x_geom's
                          scratchpad initial block: 4 halfwords per
                          entry at word 128 up -- chars 0-5 of the
                          keyword (space-padded), then
                          {var, arity[3:0], bcnt[1:0], opcode[7:0]}.
  basic/glkwtab.inc      (asm)     -> KWTAB fragment: the GL verbs as
                          native BASIC keywords, tokens GLV0 up IN
                          BASIC_VERBS ORDER, but LISTED longest-first
                          so CRUNCH's first-match never truncates
                          (MOVER3 before MOVER before MOVE; POINT3
                          and CLEARS precede the MAIN table's POINT
                          and CLS because this fragment is spliced at
                          the head of KWTAB).
  basic/glvtab.inc       (asm)     -> GLV0/GLVN equates + GLVTAB, two
                          bytes per verb in TOKEN order: opcode, then
                          {var<<7 | bcnt<<4 | word-arity}.

TOKEN ORDER IS ABI: saved .BAS files are tokenised, so BASIC_VERBS may
only be APPENDED to -- never reordered, never have entries removed.

Run:  python3 generators/gen_glkw.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

#        long      short  op    bcnt arity
VERBS = [
    ("NOOP",    "NOP",  0x01, 0, 0),
    ("FLIP",    "FL",   0x02, 0, 0),   # P8X page verbs
    ("PGSYNC",  "PS",   0x03, 0, 0),
    ("RESETF",  "RF",   0x04, 0, 0),
    ("WAIT",    "W",    0x05, 0, 1),
    ("COLOR",   "C",    0x06, 3, 3),
    ("FLOOD",   "F",    0x07, 3, 3),
    ("POINT",   "PT",   0x08, 0, 0),
    ("POINT3",  "PT3",  0x09, 0, 0),
    ("CLEARS",  "CLS",  0x0F, 3, 3),
    ("MOVE",    "M",    0x10, 0, 2),
    ("MOVER",   "MR",   0x11, 0, 2),
    ("MOVE3",   "M3",   0x12, 0, 3),
    ("MOVER3",  "MR3",  0x13, 0, 3),
    ("DRAW",    "D",    0x28, 0, 2),
    ("DRAWR",   "DR",   0x29, 0, 2),
    ("DRAW3",   "D3",   0x2A, 0, 3),
    ("DRAWR3",  "DR3",  0x2B, 0, 3),
    ("POLY",    "P",    0x30, 1, 15),
    ("POLYR",   "PR",   0x31, 1, 15),
    ("POLY3",   "P3",   0x32, 1, 15),
    ("POLYR3",  "PR3",  0x33, 1, 15),
    ("RECT",    "R",    0x34, 0, 2),
    ("RECTR",   "RR",   0x35, 0, 2),
    ("CLBEG",   "CB",   0x70, 1, 1),
    ("CLEND",   "CE",   0x71, 0, 0),
    ("CLRUN",   "CR",   0x72, 1, 1),
    ("CLOOP",   "CL",   0x73, 1, 2),
    ("CLDEL",   "CD",   0x74, 1, 1),
    ("CLAPP",   "CLA",  0x79, 1, 1),   # P8X append
    ("MDIDEN",  "MDI",  0x90, 0, 0),
    ("MDORG",   "MDO",  0x91, 0, 3),
    ("MDSCAL",  "MDS",  0x92, 0, 3),
    ("MDROTX",  "MDX",  0x93, 0, 1),
    ("MDROTY",  "MDY",  0x94, 0, 1),
    ("MDROTZ",  "MDZ",  0x95, 0, 1),
    ("MDTRAN",  "MDT",  0x96, 0, 3),
    ("MDMATX",  "MDM",  0x97, 0, 12),
    ("VWIDEN",  "VWI",  0xA0, 0, 0),
    ("VWRPT",   "VWR",  0xA1, 0, 3),
    ("VWROTX",  "VWX",  0xA3, 0, 1),
    ("VWROTY",  "VWY",  0xA4, 0, 1),
    ("VWROTZ",  "VWZ",  0xA5, 0, 1),
    ("VWMATX",  "VWM",  0xA7, 0, 9),
    ("DISTH",   "DH",   0xA8, 0, 1),
    ("DISTY",   "DY",   0xA9, 0, 1),
    ("CLIPH",   "CH",   0xAA, 1, 1),
    ("CLIPY",   "CY",   0xAB, 1, 1),
    ("CONVRT",  "CV",   0xAF, 0, 0),
    ("PROJCT",  "PRO",  0xB0, 0, 1),
    ("DISTAN",  "DS",   0xB1, 0, 1),
    ("VWPORT",  "VWP",  0xB2, 0, 4),
    ("WINDOW",  "WI",   0xB3, 0, 4),
    ("PRMFIL",  "PF",   0xE0, 1, 1),
    # stage 10f (appended: BASIC token order is ABI)
    ("LINFUN",  "LF",   0xEB, 1, 1),
    # stage 10e read-back (appended AFTER 10f: token order is ABI)
    ("FLAGRD",  "FR",   0x61, 1, 1),
    ("MATXRD",  "MX",   0x62, 1, 1),
    ("CLRD",    "CRD",  0x76, 1, 1),
    ("CLMOD",   "CM",   0x78, 2, 3),   # n b off: one-byte patch (P8X shrink)
    # stage 10g (appended: BASIC token order is ABI)
    ("AREA",    "AR",   0xC0, 0, 0),
    ("AREABC",  "ARB",  0xC1, 3, 3),
    # stage 10h (appended: BASIC token order is ABI). TEXT's arity 14 is
    # the COUNTED-STRING sentinel: the translator takes a quoted string
    # and emits count + chars; BASIC routes the token to its own string
    # handler (glvtab meta $FF). TSIZE/TANGLE are compose ALIASES
    # (MDSCAL s s s / MDROTZ d); TDEFIN records a glyph list (CLBEG's
    # shape, the glyph bank).
    ("TEXT",    "TX",   0x80, 0, 14),
    ("TSIZE",   "TS",   0x81, 0, 1),
    ("TANGLE",  "TA",   0x82, 0, 1),
    ("TDEFIN",  "TD",   0x84, 1, 1),
    # stage 10i (appended: BASIC token order is ABI). PGC's own spelling
    # (ELIPSE, one L). CIRCLE is BASIC_SKIP'd: BASIC's CIRCLE statement
    # (token $AC, screen space) owns the name -- GL "CIRCLE r" remains.
    ("CIRCLE",  "CI",   0x38, 0, 1),
    ("ELIPSE",  "EL",   0x39, 0, 2),
    ("ARC",     "ARC",  0x3C, 0, 3),
    ("SECTOR",  "SEC",  0x3D, 0, 3),
    # stage 10j (appended). AREAPT's arity 16 exceeds the ROM's 4-bit
    # field: the RTL meta encodes it as the sentinel 13 and the BASIC
    # meta as $FE; both mean "sixteen int16 words".
    ("LINPAT",  "LPT",  0xEA, 0, 1),
    ("AREAPT",  "APT",  0xE7, 0, 16),
    # stage 10k (appended). TEXTP is the SAME engine as TEXT (PGC's
    # fixed-cell/programmable split has no meaning here: P8X text IS
    # stroke text); TJUST h v justifies 1..3 left/centre/right and
    # bottom/middle/top about the current point, in model units.
    ("TEXTP",   "TXP",  0x83, 0, 14),
    ("TJUST",   "TJ",   0x85, 2, 2),
    ("CA",      "CA",   0xFE, 0, 0),   # mode switches: internal markers
    ("CX",      "CX",   0xFF, 0, 0),
]

entries = []
for lng, sht, op, b, a in VERBS:
    entries.append((lng, op, b, a))
    if sht != lng:
        entries.append((sht, op, b, a))

with open(os.path.join(HERE, "glkwtab.h"), "w") as f:
    f.write("/* glkwtab.h - GENERATED by generators/gen_glkw.py. Do not edit. */\n")
    f.write("static const struct { const char *kw; uint8_t op, bcnt, arity; }\n")
    f.write("GLKW[] = {\n")
    for kw, op, b, a in entries:
        f.write('    { "%s", 0x%02X, %d, %d },\n' % (kw, op, b, a))
    f.write("};\n#define GLKWN %d\n" % len(entries))
print("wrote generators/glkwtab.h (%d entries)" % len(entries))

with open(os.path.join(HERE, "..", "fpga", "rtl", "glkwtab.vh"), "w") as f:
    f.write("// glkwtab.vh - GENERATED by generators/gen_glkw.py. Do not edit.\n")
    f.write("// Keyword ROM in the scratchpad, 4 halfwords per entry from word\n")
    f.write("// 128: chars 0-5 space-padded, then {var,arity[3:0],bcnt[1:0],op}.\n")
    w = 128
    for kw, op, b, a in entries:
        k = (kw + "      ")[:6]
        f.write("    cmx[%d] = 16'h%02X%02X;\n" % (w,   ord(k[0]), ord(k[1])))
        f.write("    cmx[%d] = 16'h%02X%02X;\n" % (w+1, ord(k[2]), ord(k[3])))
        f.write("    cmx[%d] = 16'h%02X%02X;\n" % (w+2, ord(k[4]), ord(k[5])))
        var = 1 if a == 15 else 0
        ra = 13 if a == 16 else a          # 13 = the sixteen-word sentinel
        meta = (var << 14) | ((ra & 15) << 10) | ((b & 3) << 8) | op
        f.write("    cmx[%d] = 16'h%04X;\n" % (w+3, meta))
        w += 4
    f.write("    // %d entries; the matcher stops at the first zero word\n" % len(entries))
    f.write("    cmx[%d] = 16'h0000;\n" % w)
assert w + 1 < 768, "keyword ROM reached the RBS mirror (768) -- the AREAPT block and string buffer live above it at 784+"
assert len(entries) < 256, "matcher cursor t_ent is 8 bits -- widen it in p8x_geom.v"
print("wrote fpga/rtl/glkwtab.vh (ends at scratch word %d of 1024; RBS mirror at 768)" % (w+1))

# ---- BASIC's native GL statements ---------------------------------------
# Long forms only (BASIC style; GL "..." still takes the short forms).
# Excluded: NOOP (pointless), POINT (BASIC's POINT(x,y) function owns the
# name -- GL "POINT" remains), COLOR (BASIC's COLOR statement now feeds
# BOTH pens itself), CA/CX (mode plumbing the statement layer handles).
BASIC_SKIP = {"NOOP", "POINT", "COLOR", "CA", "CX", "CIRCLE"}
GLV0 = 0xB4
bverbs = [(l, op, b, a) for l, s, op, b, a in VERBS if l not in BASIC_SKIP]
# POINT joined the natives once BASIC's pixel-read function became
# PIXELR() and freed the name -- APPENDED (token order is ABI), not
# spliced back into its VERBS position.
bverbs.append(("POINT", 0x08, 0, 0))
assert GLV0 + len(bverbs) <= 0x100, "token space overflow"

with open(os.path.join(HERE, "..", "basic", "glkwtab.inc"), "w") as f:
    f.write("; glkwtab.inc - GENERATED by generators/gen_glkw.py. Do not edit.\n")
    f.write("; KWTAB fragment: GL verbs as native keywords, tokens $%02X up in\n" % GLV0)
    f.write("; BASIC_VERBS order (the token order is ABI). Listed LONGEST-FIRST\n")
    f.write("; so CRUNCH's first-match never truncates a longer keyword; the\n")
    f.write("; fragment sits at the head of KWTAB so POINT3/CLEARS beat the\n")
    f.write("; main table's POINT/CLS.\n")
    order = sorted(range(len(bverbs)), key=lambda i: -len(bverbs[i][0]))
    for i in order:
        f.write("        .ascii \"%s\"\n" % bverbs[i][0])
        f.write("        .byte $%02X\n" % (GLV0 + i))
print("wrote basic/glkwtab.inc (%d keywords)" % len(bverbs))

with open(os.path.join(HERE, "..", "basic", "glvtab.inc"), "w") as f:
    f.write("; glvtab.inc - GENERATED by generators/gen_glkw.py. Do not edit.\n")
    f.write("; Two bytes per verb in TOKEN order: the GL opcode, then\n")
    f.write("; {var<<7 | bcnt<<4 | word-arity}. var: a POLY count byte then\n")
    f.write("; count * (2 or 3 by opcode bit 1) int16s. Else bcnt byte params\n")
    f.write("; first, then (arity - bcnt) int16 params, little-endian.\n")
    f.write("GLV0   = $%02X\n" % GLV0)
    f.write("GLVN   = %d\n" % len(bverbs))
    f.write("GLVTAB:\n")
    for i, (lng, op, b, a) in enumerate(bverbs):
        if a == 15:
            meta = 0x80 | (b << 4)
        elif a == 14:
            meta = 0xFF          # string statement: BASIC's own handler
        elif a == 16:
            meta = 0xFE          # sixteen int16 words (AREAPT)
        else:
            meta = (b << 4) | (a - b)
        f.write("        .byte $%02X, $%02X   ; $%02X %s\n"
                % (op, meta, GLV0 + i, lng))
print("wrote basic/glvtab.inc (GLV0=$%02X GLVN=%d)" % (GLV0, len(bverbs)))
