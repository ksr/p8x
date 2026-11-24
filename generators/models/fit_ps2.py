#!/usr/bin/env python3
# Author: Claude (Anthropic) for Ken Rother, 2026
"""Render a board with its PS/2 sockets fitted (Ken, 2026-11-23: every new render of any board shows them): kicad-cli
draws a temporary copy of the board in which the mini-DIN-6 footprints have the model beside this file. The board file
is only read. A board without such sockets is drawn as it is. The same file in elf and YACC1-D (tools/models), p8x and
P32W (generators/models); plain Python, also under KiCad's own.

    python3 fit_ps2.py BOARD.kicad_pcb [kicad-cli pcb render arguments]     e.g. --side top -o top.png
    from a build:  with fit_ps2.fitted(board) as copy: ... kicad-cli pcb render ... copy
                   fit_ps2.fit_file(copy)                                   a copy already made, fitted in place
"""
import contextlib, math, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"

# footprint -> (model, the way from pad 1 to pad 2 in the model, y down as on a board); the model's origin is pad 1
SOCKETS = {
    "MiniDIN6_MD-60SM": ("MiniDIN6_MD-60SM.step", (0, 2.6)),                                  # elf, YACC1-D, ELFII-VIDEO
    "MiniDIN-6_Female_Horizontal_SameSky_MD-60SM": ("MiniDIN6_MD-60SM.step", (0, 2.6)),       # P32W
    "MiniDIN6_RA_PS2": ("MiniDIN6_RA_PS2-body.step", (0, -2.6)),                              # P8X
}


def _end(text, i):
    """the end of the bracketed block that starts at text[i]"""
    depth = 0
    while True:
        c = text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        elif c == '"':
            i += 1
            while text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        i += 1


def fit(text):
    """(the board's text with a model in each PS/2 socket that has none, how many)"""
    out, last, n = [], 0, 0
    for m in re.finditer(r'\(footprint\s+"(?:[^":]*:)?([^"]*)"', text):
        if m.group(1) not in SOCKETS:
            continue
        end = _end(text, m.start())
        block = text[m.start():end]
        pads = {p: (float(x), float(y)) for p, x, y in
                re.findall(r'\(pad\s+"([12])"[^(]*\(at\s+([-\d.]+)\s+([-\d.]+)', block)}
        if "(model" in block or len(pads) != 2:
            continue
        model, way = SOCKETS[m.group(1)]
        (ax, ay), (bx, by) = pads["1"], pads["2"]
        turn = math.degrees(math.atan2(-(by - ay), bx - ax) - math.atan2(-way[1], way[0]))
        out += [text[last:end - 1], '(model "%s" (offset (xyz %.4f %.4f 0)) (scale (xyz 1 1 1)) (rotate (xyz 0 0 %d)))\n'
                % (os.path.join(HERE, model), ax, -ay, -int(round(turn / 90.0)) * 90 % 360)]   # KiCad turns them clockwise
        last, n = end - 1, n + 1
    return "".join(out + [text[last:]]), n


def fit_file(path):
    """fit a copy of a board in place (never the board itself)"""
    with open(path, encoding="utf-8") as f:
        text, n = fit(f.read())
    if n:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    return n


@contextlib.contextmanager
def fitted(board):
    """the path of a copy with the sockets fitted, beside the board (the same project and libraries), removed afterwards;
    the board's own path when it has none to fit"""
    with open(board, encoding="utf-8") as f:
        text, n = fit(f.read())
    if not n:
        yield board
        return
    h, copy = tempfile.mkstemp(prefix=".ps2-fitted-", suffix=".kicad_pcb", dir=os.path.dirname(os.path.abspath(board)))
    try:
        with os.fdopen(h, "w", encoding="utf-8") as f:
            f.write(text)
        yield copy
    finally:
        for p in (copy, copy[:-len("kicad_pcb")] + "kicad_prl"):
            if os.path.exists(p):
                os.remove(p)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    with fitted(sys.argv[1]) as b:
        sys.exit(subprocess.call([CLI, "pcb", "render"] + sys.argv[2:] + [b]))
