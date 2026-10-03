#!/bin/sh
# build.sh -- render the assembled P8X: the backplane with every plug-in card in
# its DIN 41612 slot (generators/render_assembly.py).
#
#   sh hardware/assembly/build.sh            # scratch in $TMPDIR/p8x-assembly
#   sh hardware/assembly/build.sh <scratch>  # or a scratch directory of your own
#
# The boards are only read: each one is copied into the scratch directory, and
# the card STEPs and the assembly board are built there. Only the PNG renders are
# written here. Needs KiCad 10. Takes a few minutes (eight STEP exports + three
# high-quality renders).
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
SCRATCH="${1:-${TMPDIR:-/tmp}/p8x-assembly}"
"$PYK" "$ROOT/generators/render_assembly.py" --scratch "$SCRATCH" --out "$HERE" 2>&1 |
    grep -viE 'Debug:|assert|wxApp|handler|Fontconfig'
