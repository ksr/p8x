#!/usr/bin/env python3
"""gen_placement.py -- parts-placement PDF for the memory card, centred on the
sheet, showing the same info as the silkscreen (reference designators, part
values, function + jumper labels).

Run under KiCad's bundled python (needs pcbnew); it shells out to kicad-cli for
the PDF plot. It is regenerated as part of the build -- import_ses.py calls
build() after the routing is imported, so the drawing always matches the board.
It can also be run on its own:

  PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
  "$PYK" hardware/memory-card/kicad/gen_placement.py

The board plotted by kicad-cli sits at its own PCB coordinates on the page, so a
straight plot lands in a page corner. We centre it by shifting every item onto
the middle of an A4-landscape sheet on a THROWAWAY copy -- the real board file is
never modified.
"""
import os, sys, subprocess, pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
CLI  = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
BRD  = os.path.join(HERE, "p8x-memory-card.kicad_pcb")
OUT  = os.path.join(HERE, "p8x-memory-card-placement.pdf")
TMP  = "/tmp/p8x-memory-card-placement.kicad_pcb"  # temp; name shows in the title block
TITLE_BLOCK = ('  (title_block\n'
               '    (title "P8X Memory Card -- Parts Placement (rev F)")\n'
               '    (rev "F")\n    (company "P8X")\n  )\n')

def build():
    b = pcbnew.LoadBoard(BRD)
    pw, ph = pcbnew.FromMM(297.0), pcbnew.FromMM(210.0)   # A4 landscape page
    bb = b.GetBoardEdgesBoundingBox(); c = bb.GetCenter()
    shift = pcbnew.VECTOR2I(pw // 2 - c.x, ph // 2 - c.y)
    for it in (list(b.GetFootprints()) + list(b.GetTracks())
               + list(b.GetDrawings()) + list(b.Zones())):
        it.Move(shift)
    pcbnew.SaveBoard(TMP, b)
    # give the sheet a clean title block (kept off the real board)
    t = open(TMP).read().replace('(paper "A4")\n', '(paper "A4")\n' + TITLE_BLOCK, 1)
    open(TMP, "w").write(t)
    # --black-and-white so refs AND values plot as crisp black (the silkscreen
    # layer colour is pale); a placement drawing wants a clean line look anyway.
    subprocess.run([CLI, "pcb", "export", "pdf",
                    "--layers", "F.Silkscreen,F.Fab,Edge.Cuts",
                    "--black-and-white", "--include-border-title",
                    "-o", OUT, TMP], check=True)
    os.remove(TMP)
    print("wrote", OUT)

if __name__ == "__main__":
    build()
