#!/bin/sh
# p8xasm `.include "file"`: a source can splice a shared equates file (resolved
# relative to the including file), so committed files like the generated memmap.inc
# can be referenced instead of cat-ed in at build time. Checks: (1) symbols from an
# included file resolve; (2) nested includes work; (3) a cycle is a hard error.
set -e
cd "$(dirname "$0")"
ROOT=../..
ASM="python3 $ROOT/assembler/p8xasm.py"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail() { echo "ASM-INCLUDE TEST: FAIL — $1"; exit 1; }

# (1)+(2) nested includes: main -> a.inc -> b.inc, symbols used across levels.
printf 'BVAL = $42\n'          > "$W/b.inc"
printf '.include "b.inc"\nAADDR = $6A00\n' > "$W/a.inc"
printf '.include "a.inc"\n        .org $2000\n        LDA #BVAL\n        STA AADDR\n        HLT\n' > "$W/main.asm"
$ASM "$W/main.asm" -o "$W/main.bin" --base 0x2000 >/dev/null 2>&1 \
    || fail "assembling a program with nested .include failed"
# LDA #$42 = 10 42 ; STA $6A00 = 14 00 6A ; HLT = 01  -> 6 bytes
sz=$(wc -c < "$W/main.bin" | tr -d ' ')
[ "$sz" = "6" ] || fail "expected 6 bytes, got $sz"
od -An -tx1 "$W/main.bin" | tr -d ' \n' | grep -qi '^1042140' \
    || fail "included symbols BVAL/AADDR did not resolve to the expected bytes"

# (3) cycle detection: a.inc includes itself.
printf '.include "self.inc"\n' > "$W/self.inc"
if $ASM "$W/self.inc" -o "$W/x.bin" --base 0x2000 >/dev/null 2>&1; then
    fail "an .include cycle should be an error"
fi

echo "ASM-INCLUDE TEST: PASS"
