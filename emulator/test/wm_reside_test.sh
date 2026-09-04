#!/bin/sh
# The load-bearing assumption of the resident window manager: a region
# reserved HIGH in RAM (WMBASE..$F800) survives a program launching into
# the TPA below it and exiting. The resident GUI kernel will live there,
# loaded once by `desk`; apps launch beneath it and must not touch it.
#
# One program writes a sentinel at WMBASE ($D800); a second program --
# compiled with CSTACKTOP=WMBASE so its C stack cannot grow into the
# kernel -- runs, does real work (a deep-ish call chain + a buffer), and
# checks the sentinel is intact. If this ever fails, the resident-WM
# memory split is unsafe and must be revisited.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "WM-RESIDE TEST: FAIL — $1"; exit 1; }

# WMBASE from the single-source memory map, never hardcoded
WMBASE=$(python3 -c "import sys; sys.path.insert(0,'$ROOT/generators'); import memmap; print(memmap.WMBASE)")

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > wr_poke.c <<EOF
/* stamp the reserved region, then exit to the shell */
int main() {
    poke($WMBASE + 0, 0x50); poke($WMBASE + 1, 0x38);
    poke($WMBASE + 2, 0x57); poke($WMBASE + 3, 0x4D);   /* "P8WM" */
    poke($WMBASE + 4, 0xDE); poke($WMBASE + 5, 0xAD);
    poke($WMBASE + 6, 0xBE); poke($WMBASE + 7, 0xEF);
    puts("POKED");
    return 0;
}
EOF
cat > wr_work.c <<EOF
/* a TPA app that does real work with a low stack, then checks the
 * reserved region is untouched (the app's own memory is all below it) */
char buf[400];
int depth(int n) { if (n == 0) { return 0; } buf[n & 255] = n; return depth(n - 1) + 1; }
int main() {
    int ok;
    depth(200);
    ok = 1;
    if (peek($WMBASE + 0) != 0x50) { ok = 0; }
    if (peek($WMBASE + 4) != 0xDE) { ok = 0; }
    if (peek($WMBASE + 7) != 0xEF) { ok = 0; }
    if (ok) { puts("INTACT"); } else { puts("CLOBBERED"); }
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py wr_poke.c -o wr_poke.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py wr_poke.asm -o wr_poke.bin --base 0x6A00 >/dev/null
# the working app links with CSTACKTOP = WMBASE (its stack stays below the kernel)
python3 $ROOT/compiler/p8cc.py wr_work.c -o wr_work.asm --cstacktop $WMBASE >/dev/null
python3 $ROOT/assembler/p8xasm.py wr_work.asm -o wr_work.bin --base 0x6A00 >/dev/null

rm -f wr.img
python3 $ROOT/tools/p8xfs.py create wr.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   wr.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  wr.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    wr.img wr_poke.bin --name /bin/pk.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wr.img wr_work.bin --name /bin/wk.bin --load 0x6A00 --exec 0x6A00 >/dev/null

printf 'B\rrun /bin/pk.bin\rrun /bin/wk.bin\rexit\r' > wr.in
../p8xemu -N -i wr.in -c wr.img -l 600000000 eeprom.bin > wr.out 2>/dev/null || true
out=$(tr -d '\0' < wr.out)
echo "$out" | grep -q "POKED"  || fail "the stamp program did not run"
echo "$out" | grep -q "INTACT" || fail "reserved region CLOBBERED by a TPA app -- the split at $WMBASE is unsafe"

echo "WM-RESIDE TEST: PASS (WMBASE $WMBASE survives a TPA program launch + exit)"
