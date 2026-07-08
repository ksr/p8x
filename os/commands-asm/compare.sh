#!/bin/sh
# compare.sh — size scoreboard for the commands-asm experiment.
#
# For every /BIN command, build the p8cc-compiled binary from os/commands/NAME.c
# and (if a hand-written os/commands-asm/NAME.asm exists) the hand-assembled
# binary, then print a table of fill-binary sizes and the size ratio. This is
# the whole point of the experiment: how much smaller is hand asm than the
# current p8cc codegen?
#
# Both are assembled with the SAME assembler (assembler/p8xasm.py, --base 0x7A00)
# so the comparison is code size only. p8cc first splices //#use libs (clib.py).
#
#     sh os/commands-asm/compare.sh
#
# Run from anywhere; paths are resolved relative to this script.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && cd .. && pwd)
CDIR="$ROOT/os/commands"
ADIR="$ROOT/os/commands-asm"
WORK="$HERE/.build"
mkdir -p "$WORK"

ASM="python3 $ROOT/assembler/p8xasm.py"
CC="python3 $ROOT/compiler/p8cc.py"
CLIB="python3 $ROOT/tools/clib.py"

ALL="cat cp diff dir find grep head more mv pwd sed sort tail tree uniq vi wc"

ratio() {   # $1=p8cc bytes $2=asm bytes -> "N.Nx" (integer math, no awk)
    r=$(( ($1 * 10 + $2 / 2) / $2 ))
    printf '%d.%dx' $((r / 10)) $((r % 10))
}

printf '%-8s %10s %10s %8s\n' CMD p8cc hand-asm ratio
printf '%-8s %10s %10s %8s\n' --- ---- -------- -----
tot_c=0; tot_a=0
for cmd in $ALL; do
    csz=""; asz=""
    if [ -f "$CDIR/$cmd.c" ]; then
        $CLIB "$CDIR/$cmd.c" -o "$WORK/$cmd.pp.c" 2>/dev/null
        $CC "$WORK/$cmd.pp.c" -o "$WORK/${cmd}_c.asm" >/dev/null 2>&1
        $ASM "$WORK/${cmd}_c.asm" -o "$WORK/${cmd}_c.bin" --base 0x7A00 >/dev/null 2>&1
        csz=$(wc -c < "$WORK/${cmd}_c.bin" | tr -d ' ')
    fi
    if [ -f "$ADIR/$cmd.asm" ]; then
        sh "$ADIR/mkasm.sh" "$cmd" > "$WORK/${cmd}_full.asm"
        $ASM "$WORK/${cmd}_full.asm" -o "$WORK/${cmd}_a.bin" --base 0x7A00 >/dev/null 2>&1
        asz=$(wc -c < "$WORK/${cmd}_a.bin" | tr -d ' ')
    fi
    ratio="-"
    if [ -n "$csz" ] && [ -n "$asz" ] && [ "$asz" -gt 0 ]; then
        ratio=$(ratio "$csz" "$asz")
        tot_c=$((tot_c + csz)); tot_a=$((tot_a + asz))
    fi
    printf '%-8s %10s %10s %8s\n' "$cmd" "${csz:--}" "${asz:--}" "$ratio"
done
printf '%-8s %10s %10s %8s\n' --- ---- -------- -----
if [ "$tot_a" -gt 0 ]; then
    printf '%-8s %10s %10s %8s   (ported commands only)\n' TOTAL "$tot_c" "$tot_a" \
        "$(ratio "$tot_c" "$tot_a")"
fi
