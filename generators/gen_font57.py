#!/usr/bin/env python3
"""gen_font57.py — the 5x7 glyph table used by BASIC's GTEXT statement.

Writes basic/font57.inc, which basic/p8xbasic.asm .includes. As with every
generator here, the SOURCE OF TRUTH is this file: edit a glyph in the ASCII art
below and regenerate, never hand-patch the .inc.

Why a 5x7 font and only 64 glyphs:
  - 5x7 in a 6x8 cell gives 40 columns on a 240-pixel-wide screen. An 8x8 font
    would give 26, and on a display this small the column count is the whole
    argument.
  - Codes $20..$5F only (space through underscore: punctuation, digits, and
    UPPERCASE). Lowercase is folded to uppercase by the renderer, which is what
    8-bit machines have always done and costs 160 bytes less than carrying a
    second alphabet. Anything outside the range renders as a blank.

Encoding: COLUMN-major, 5 bytes per glyph, one byte per column left to right.
Within a byte bit 0 is the top row and bit 6 the bottom; bit 7 is unused. That
is the order GTEXT wants, because it walks a column while shifting the byte
right, which is one SHR per pixel and no masking table.
"""
import os, sys

# Each glyph is 7 rows of 5 columns. '#' lights a pixel, anything else does not.
GLYPHS = {
' ': ("     ","     ","     ","     ","     ","     ","     "),
'!': ("  #  ","  #  ","  #  ","  #  ","  #  ","     ","  #  "),
'"': (" # # "," # # ","     ","     ","     ","     ","     "),
'#': (" # # "," # # ","#####"," # # ","#####"," # # "," # # "),
'$': ("  #  "," ####","# #  "," ### ","  # #","#### ","  #  "),
'%': ("##   ","##  #","   # ","  #  "," #   ","#  ##","   ##"),
'&': (" ##  ","#  # ","# #  "," #   ","# # #","#  # "," ## #"),
"'": ("  #  ","  #  ","     ","     ","     ","     ","     "),
'(': ("   # ","  #  "," #   "," #   "," #   ","  #  ","   # "),
')': (" #   ","  #  ","   # ","   # ","   # ","  #  "," #   "),
'*': ("     ","# # #"," ### ","#####"," ### ","# # #","     "),
'+': ("     ","  #  ","  #  ","#####","  #  ","  #  ","     "),
',': ("     ","     ","     ","     ","  ## ","  #  "," #   "),
'-': ("     ","     ","     ","#####","     ","     ","     "),
'.': ("     ","     ","     ","     ","     "," ##  "," ##  "),
'/': ("    #","   # ","  #  ","  #  ","  #  "," #   ","#    "),
'0': (" ### ","#   #","#  ##","# # #","##  #","#   #"," ### "),
'1': ("  #  "," ##  ","  #  ","  #  ","  #  ","  #  "," ### "),
'2': (" ### ","#   #","    #","   # ","  #  "," #   ","#####"),
'3': ("#####","   # ","  #  ","   # ","    #","#   #"," ### "),
'4': ("   # ","  ## "," # # ","#  # ","#####","   # ","   # "),
'5': ("#####","#    ","#### ","    #","    #","#   #"," ### "),
'6': ("  ## "," #   ","#    ","#### ","#   #","#   #"," ### "),
'7': ("#####","    #","   # ","  #  "," #   "," #   "," #   "),
'8': (" ### ","#   #","#   #"," ### ","#   #","#   #"," ### "),
'9': (" ### ","#   #","#   #"," ####","    #","   # "," ##  "),
':': ("     "," ##  "," ##  ","     "," ##  "," ##  ","     "),
';': ("     "," ##  "," ##  ","     "," ##  ","  #  "," #   "),
'<': ("   # ","  #  "," #   ","#    "," #   ","  #  ","   # "),
'=': ("     ","     ","#####","     ","#####","     ","     "),
'>': (" #   ","  #  ","   # ","    #","   # ","  #  "," #   "),
'?': (" ### ","#   #","    #","   # ","  #  ","     ","  #  "),
'@': (" ### ","#   #","    #"," ## #","# # #","# # #"," ####"),
'A': ("  #  "," # # ","#   #","#   #","#####","#   #","#   #"),
'B': ("#### ","#   #","#   #","#### ","#   #","#   #","#### "),
'C': (" ### ","#   #","#    ","#    ","#    ","#   #"," ### "),
'D': ("###  ","#  # ","#   #","#   #","#   #","#  # ","###  "),
'E': ("#####","#    ","#    ","#### ","#    ","#    ","#####"),
'F': ("#####","#    ","#    ","#### ","#    ","#    ","#    "),
'G': (" ### ","#   #","#    ","#  ##","#   #","#   #"," ####"),
'H': ("#   #","#   #","#   #","#####","#   #","#   #","#   #"),
'I': (" ### ","  #  ","  #  ","  #  ","  #  ","  #  "," ### "),
'J': ("  ###","   # ","   # ","   # ","   # ","#  # "," ##  "),
'K': ("#   #","#  # ","# #  ","##   ","# #  ","#  # ","#   #"),
'L': ("#    ","#    ","#    ","#    ","#    ","#    ","#####"),
'M': ("#   #","## ##","# # #","# # #","#   #","#   #","#   #"),
'N': ("#   #","#   #","##  #","# # #","#  ##","#   #","#   #"),
'O': (" ### ","#   #","#   #","#   #","#   #","#   #"," ### "),
'P': ("#### ","#   #","#   #","#### ","#    ","#    ","#    "),
'Q': (" ### ","#   #","#   #","#   #","# # #","#  # "," ## #"),
'R': ("#### ","#   #","#   #","#### ","# #  ","#  # ","#   #"),
'S': (" ####","#    ","#    "," ### ","    #","    #","#### "),
'T': ("#####","  #  ","  #  ","  #  ","  #  ","  #  ","  #  "),
'U': ("#   #","#   #","#   #","#   #","#   #","#   #"," ### "),
'V': ("#   #","#   #","#   #","#   #","#   #"," # # ","  #  "),
'W': ("#   #","#   #","#   #","# # #","# # #","## ##","#   #"),
'X': ("#   #","#   #"," # # ","  #  "," # # ","#   #","#   #"),
'Y': ("#   #","#   #"," # # ","  #  ","  #  ","  #  ","  #  "),
'Z': ("#####","    #","   # ","  #  "," #   ","#    ","#####"),
'[': (" ### "," #   "," #   "," #   "," #   "," #   "," ### "),
'\\':("#    "," #   ","  #  ","  #  ","  #  ","   # ","    #"),
']': (" ### ","   # ","   # ","   # ","   # ","   # "," ### "),
'^': ("  #  "," # # ","#   #","     ","     ","     ","     "),
'_': ("     ","     ","     ","     ","     ","     ","#####"),
}

FIRST, LAST = 0x20, 0x5F
W, H = 5, 7


def columns(art):
    """7 rows of 5 chars -> 5 column bytes, bit 0 = top row."""
    if len(art) != H or any(len(r) != W for r in art):
        raise ValueError("glyph must be %d rows of %d columns" % (H, W))
    out = []
    for x in range(W):
        b = 0
        for y in range(H):
            if art[y][x] == '#':
                b |= 1 << y
        out.append(b)
    return out


def render(cols):
    """Inverse of columns(), so the round-trip can be checked."""
    return tuple("".join('#' if cols[x] >> y & 1 else ' ' for x in range(W))
                 for y in range(H))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, os.pardir, 'basic', 'font57.inc')

    missing = [c for c in range(FIRST, LAST + 1) if chr(c) not in GLYPHS]
    if missing:
        sys.exit("gen_font57: no glyph for %s" % " ".join(hex(c) for c in missing))

    lines = [
        "; font57.inc -- GENERATED by generators/gen_font57.py, do not edit.",
        ";",
        "; 5x7 glyphs for codes $20..$5F, five COLUMN bytes each, left to right.",
        "; Bit 0 of a byte is the top row and bit 6 the bottom, which lets GTEXT",
        "; walk a column with one SHR per pixel. %d glyphs, %d bytes." % (
            LAST - FIRST + 1, (LAST - FIRST + 1) * W),
        "FONT57:",
    ]
    total = 0
    for code in range(FIRST, LAST + 1):
        ch = chr(code)
        cols = columns(GLYPHS[ch])
        if render(cols) != GLYPHS[ch]:
            sys.exit("gen_font57: round-trip failed for %r" % ch)
        total += len(cols)
        label = "space" if ch == ' ' else ch
        lines.append("        .byte %s   ; $%02X %s" % (
            ",".join("$%02X" % b for b in cols), code, label))
    lines.append("FONT57E:")
    lines.append("")

    with open(out, 'w') as f:
        f.write("\n".join(lines))
    print("wrote %s (%d glyphs, %d bytes)" % (
        os.path.relpath(out, os.getcwd()), LAST - FIRST + 1, total))


if __name__ == '__main__':
    main()
