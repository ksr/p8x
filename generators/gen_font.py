#!/usr/bin/env python3
"""gen_font.py - the stage-10h stroke font, GENERATOR of os/font.gl.

A glyph IS a command list (STAGE10-DESIGN.md): relative pen-up moves
(MOVER3) and pen-down strokes (DRAWR3), ending with a pen-up advance to
the next character cell -- so TSIZE (MDSCAL) and TANGLE (MDROTZ) scale
and rotate both the strokes AND the baseline walk through the ordinary
compose path, nothing text-specific in the datapath.

Design grid: x 0..4, y 0..6 (y UP, baseline y=0, comma/semicolon dip to
-1), advance 6. TSIZE 256 (1.0) therefore draws 7-unit-tall capitals
with a 6-unit pitch, in window units.

Coverage: ASCII 32..95 -- the glyph bank has 64 slots, exactly space
through underscore. Lowercase folds to uppercase in TEXT itself. A dot
is a zero-length DRAWR3 (the device draws one pixel).

The output is ASCII graphics language, one TDEFIN..CLEND line per
glyph, wrapped CA ... CX so `gl /font.gl` streams it verbatim.

Run:  python3 generators/gen_font.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ADV = 6                                   # cell pitch in design units

# glyph strokes: char -> list of polylines, absolute (x, y) grid points.
# A single-point polyline is a dot.
F = {
    ' ': [],
    '!': [[(2, 6), (2, 2)], [(2, 0)]],
    '"': [[(1, 6), (1, 4)], [(3, 6), (3, 4)]],
    '#': [[(1, 0), (1, 6)], [(3, 0), (3, 6)],
          [(0, 2), (4, 2)], [(0, 4), (4, 4)]],
    '$': [[(4, 5), (3, 6), (1, 6), (0, 5), (0, 4), (1, 3), (3, 3),
           (4, 2), (4, 1), (3, 0), (1, 0), (0, 1)], [(2, 6), (2, 0)]],
    '%': [[(0, 6), (1, 6), (1, 5), (0, 5), (0, 6)],
          [(3, 1), (4, 1), (4, 0), (3, 0), (3, 1)],
          [(0, 0), (4, 6)]],
    '&': [[(4, 0), (1, 4), (1, 5), (2, 6), (3, 5), (3, 4),
           (0, 1), (1, 0), (2, 0), (4, 2)]],
    "'": [[(2, 6), (2, 4)]],
    '(': [[(3, 6), (2, 5), (2, 1), (3, 0)]],
    ')': [[(1, 6), (2, 5), (2, 1), (1, 0)]],
    '*': [[(2, 5), (2, 1)], [(0, 4), (4, 2)], [(0, 2), (4, 4)]],
    '+': [[(2, 5), (2, 1)], [(0, 3), (4, 3)]],
    ',': [[(2, 1), (1, -1)]],
    '-': [[(0, 3), (4, 3)]],
    '.': [[(2, 0)]],
    '/': [[(0, 0), (4, 6)]],
    '0': [[(1, 0), (0, 1), (0, 5), (1, 6), (3, 6), (4, 5), (4, 1),
           (3, 0), (1, 0)], [(0, 1), (4, 5)]],
    '1': [[(1, 5), (2, 6), (2, 0)], [(1, 0), (3, 0)]],
    '2': [[(0, 5), (1, 6), (3, 6), (4, 5), (4, 4), (0, 0), (4, 0)]],
    '3': [[(0, 5), (1, 6), (3, 6), (4, 5), (4, 4), (3, 3), (2, 3)],
          [(3, 3), (4, 2), (4, 1), (3, 0), (1, 0), (0, 1)]],
    '4': [[(3, 0), (3, 6), (0, 2), (4, 2)]],
    '5': [[(4, 6), (0, 6), (0, 3), (3, 3), (4, 2), (4, 1), (3, 0),
           (1, 0), (0, 1)]],
    '6': [[(3, 6), (1, 6), (0, 5), (0, 1), (1, 0), (3, 0), (4, 1),
           (4, 2), (3, 3), (0, 3)]],
    '7': [[(0, 6), (4, 6), (1, 0)]],
    '8': [[(1, 3), (0, 4), (0, 5), (1, 6), (3, 6), (4, 5), (4, 4),
           (3, 3), (1, 3), (0, 2), (0, 1), (1, 0), (3, 0), (4, 1),
           (4, 2), (3, 3)]],
    '9': [[(1, 0), (3, 0), (4, 1), (4, 5), (3, 6), (1, 6), (0, 5),
           (0, 4), (1, 3), (4, 3)]],
    ':': [[(2, 4)], [(2, 1)]],
    ';': [[(2, 4)], [(2, 1), (1, -1)]],
    '<': [[(4, 6), (0, 3), (4, 0)]],
    '=': [[(0, 4), (4, 4)], [(0, 2), (4, 2)]],
    '>': [[(0, 6), (4, 3), (0, 0)]],
    '?': [[(0, 5), (1, 6), (3, 6), (4, 5), (4, 4), (2, 2)], [(2, 0)]],
    '@': [[(3, 0), (1, 0), (0, 1), (0, 5), (1, 6), (3, 6), (4, 5),
           (4, 2), (3, 2), (2, 2), (2, 4), (3, 4)]],
    'A': [[(0, 0), (2, 6), (4, 0)], [(1, 2), (3, 2)]],
    'B': [[(0, 0), (0, 6), (3, 6), (4, 5), (4, 4), (3, 3), (0, 3)],
          [(3, 3), (4, 2), (4, 1), (3, 0), (0, 0)]],
    'C': [[(4, 1), (3, 0), (1, 0), (0, 1), (0, 5), (1, 6), (3, 6),
           (4, 5)]],
    'D': [[(0, 0), (0, 6), (2, 6), (4, 4), (4, 2), (2, 0), (0, 0)]],
    'E': [[(4, 0), (0, 0), (0, 6), (4, 6)], [(0, 3), (3, 3)]],
    'F': [[(0, 0), (0, 6), (4, 6)], [(0, 3), (3, 3)]],
    'G': [[(4, 5), (3, 6), (1, 6), (0, 5), (0, 1), (1, 0), (3, 0),
           (4, 1), (4, 3), (2, 3)]],
    'H': [[(0, 0), (0, 6)], [(4, 0), (4, 6)], [(0, 3), (4, 3)]],
    'I': [[(1, 0), (3, 0)], [(2, 0), (2, 6)], [(1, 6), (3, 6)]],
    'J': [[(0, 1), (1, 0), (3, 0), (4, 1), (4, 6)]],
    'K': [[(0, 0), (0, 6)], [(0, 2), (4, 6)], [(1, 3), (4, 0)]],
    'L': [[(0, 6), (0, 0), (4, 0)]],
    'M': [[(0, 0), (0, 6), (2, 3), (4, 6), (4, 0)]],
    'N': [[(0, 0), (0, 6), (4, 0), (4, 6)]],
    'O': [[(1, 0), (0, 1), (0, 5), (1, 6), (3, 6), (4, 5), (4, 1),
           (3, 0), (1, 0)]],
    'P': [[(0, 0), (0, 6), (3, 6), (4, 5), (4, 4), (3, 3), (0, 3)]],
    'Q': [[(1, 0), (0, 1), (0, 5), (1, 6), (3, 6), (4, 5), (4, 1),
           (3, 0), (1, 0)], [(2, 2), (4, 0)]],
    'R': [[(0, 0), (0, 6), (3, 6), (4, 5), (4, 4), (3, 3), (0, 3)],
          [(2, 3), (4, 0)]],
    'S': [[(4, 5), (3, 6), (1, 6), (0, 5), (0, 4), (1, 3), (3, 3),
           (4, 2), (4, 1), (3, 0), (1, 0), (0, 1)]],
    'T': [[(0, 6), (4, 6)], [(2, 6), (2, 0)]],
    'U': [[(0, 6), (0, 1), (1, 0), (3, 0), (4, 1), (4, 6)]],
    'V': [[(0, 6), (2, 0), (4, 6)]],
    'W': [[(0, 6), (1, 0), (2, 3), (3, 0), (4, 6)]],
    'X': [[(0, 0), (4, 6)], [(0, 6), (4, 0)]],
    'Y': [[(0, 6), (2, 3), (4, 6)], [(2, 3), (2, 0)]],
    'Z': [[(0, 6), (4, 6), (0, 0), (4, 0)]],
    '[': [[(3, 6), (2, 6), (2, 0), (3, 0)]],
    '\\': [[(0, 6), (4, 0)]],
    ']': [[(1, 6), (2, 6), (2, 0), (1, 0)]],
    '^': [[(0, 4), (2, 6), (4, 4)]],
    '_': [[(0, 0), (4, 0)]],
}


def glyph_line(ch):
    """One 'TD c ... CE' ASCII line: strokes as relative ops from the
    cell origin, then the pen-up advance to the next origin."""
    ops = []
    cx, cy = 0, 0
    for poly in F[ch]:
        x0, y0 = poly[0]
        if (x0 - cx, y0 - cy) != (0, 0) or not ops:
            ops.append("MR3 %d %d 0" % (x0 - cx, y0 - cy))
        cx, cy = x0, y0
        if len(poly) == 1:                    # a dot: zero-length stroke
            ops.append("DR3 0 0 0")
        for x, y in poly[1:]:
            ops.append("DR3 %d %d 0" % (x - cx, y - cy))
            cx, cy = x, y
    ops.append("MR3 %d %d 0" % (ADV - cx, -cy))   # the baseline advance
    return "TD %d %s CE" % (ord(ch), " ".join(ops))


def main():
    missing = [c for c in range(32, 96) if chr(c) not in F]
    assert not missing, "glyphs missing: %r" % [chr(c) for c in missing]
    out = os.path.join(HERE, "..", "os", "font.gl")
    with open(out, "w", newline="\n") as f:
        f.write("CA \n")    # the hex-mode transport switch is LITERALLY
        #                     "CA " -- the space is part of the sequence
        for c in range(32, 96):
            f.write(glyph_line(chr(c)) + "\n")
        f.write("CX ")      # no trailing newline: after CX the port is
        #                     back in HEX mode, where a stray 0A errors
    n = os.path.getsize(out)
    print("wrote os/font.gl (%d glyphs, %d bytes)" % (96 - 32, n))


if __name__ == "__main__":
    main()
