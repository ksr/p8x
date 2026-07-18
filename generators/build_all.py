#!/usr/bin/env python3
"""Regenerate EVERY hardware artifact from source, in dependency order.

One command instead of remembering four scripts (it was a forgotten renderer that
let the backplane schematic PDF drift). Run from anywhere:

    python3 generators/build_all.py

Order matters: gen_eagle writes the .sch/.brd (the Eagle source of truth); the
three PDF renderers then draw from those / from the netlist. All PDFs render in
reportlab invariant mode (fixed date + content-derived id), so a re-render with no
source change is byte-identical -- which is what makes check_artifacts.py able to
tell "stale commit" from "nothing changed". See check_artifacts.py for the gate.
"""
import subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
HW   = os.path.join(os.path.dirname(HERE), "hardware")

# (script, cwd) — gen_eagle must run with cwd=hardware/ (it writes <card>/... there)
STEPS = [
    ("gen_eagle.py",               HW),    # .sch + .brd for all 9 boards
    ("render_traditional_auto.py", HERE),  # per-card schematic PDFs (data-driven)
    ("render_board_pdf.py",        HERE),  # per-board placement PDFs (from .brd)
    ("render_bp_traditional.py",   HERE),  # backplane schematic PDF (bus-derived)
]

def main():
    for script, cwd in STEPS:
        print("=== %s ===" % script)
        r = subprocess.run([sys.executable, os.path.join(HERE, script)], cwd=cwd)
        if r.returncode != 0:
            print("FAILED: %s (exit %d)" % (script, r.returncode))
            return r.returncode
    print("all hardware artifacts regenerated")
    return 0

if __name__ == "__main__":
    sys.exit(main())
