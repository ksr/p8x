#!/bin/sh
# mkasm.sh NAME  — emit the full assembler source for command NAME to stdout:
# its os/commands-asm/NAME.asm followed by each shared include it declares with
# a `;#use <lib>` line (-> lib_<lib>.inc). This mirrors the C side's clib.py
# `//#use` splicing, so a hand-asm command shares helpers (stdin/glob) the same
# way the C command shares lib_*.c — and each command's binary therefore counts
# the shared code, keeping the size comparison apples-to-apples.
here=$(cd "$(dirname "$0")" && pwd)
f="$here/$1.asm"
cat "$f"
# only a directive at the very start of a line counts (not a mention in prose),
# and each lib is included at most once
grep -oE '^;#use [a-z_]+' "$f" 2>/dev/null | awk '{print $2}' | sort -u | while read -r lib; do
    echo
    cat "$here/lib_$lib.inc"
done
