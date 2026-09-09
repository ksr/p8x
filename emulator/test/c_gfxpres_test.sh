#!/bin/sh
# P1 of the two-mode design (docs/p8x-two-mode-design.md): the graphics_present
# flag. The monitor probes GLID at wake, records the result in the resident
# GFXPRES byte ($60A4), and prints "GRAPHICS AVAILABLE" / "NO GRAPHICS" on serial;
# the OS re-affirms GFXPRES at boot; every GL program reads it via has_graphics()
# (and gpresent(), which now sources presence from the flag rather than a fresh
# GLID probe). The emulator's -ng flag floats GLID to $FF, so BOTH modes are
# testable from one build: this test boots the SAME disk with and without -ng and
# checks that the monitor message, the flag a program reads, and a real GL
# program's run-vs-"?No display" all track the mode.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GFXPRES TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

# The probe reports what a program sees: has_graphics() (the lib helper that reads
# GFXPRES) and gpresent() (the mandatory-first-call, now flag-sourced). It then
# uses the EXACT idiom every shipped GL program opens with -- gpresent()==0 ->
# "?No display" + exit -- so this covers the real headless-exit path without a
# second binary. test/*.c is gitignored build scratch, so generate it here to
# keep the test self-contained.
cat > gp_probe.c <<'PROBEEOF'
//#use gfx
int main() {
    if (has_graphics()) { puts("HAS=1"); } else { puts("HAS=0"); }
    if (gpresent() == 0) { puts("?No display"); return 1; }
    puts("GPR=1");
    return 0;
}
PROBEEOF

cp $ROOT/os/commands/lib_gfx.c .          # clib resolves //#use from the source's dir
python3 $ROOT/tools/clib.py gp_probe.c -o gp_probe_x.c
python3 $ROOT/compiler/p8cc.py gp_probe_x.c -o gp_probe.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gp_probe.asm -o gp_probe.bin --base 0x6A00 >/dev/null

rm -f gp.img
python3 $ROOT/tools/p8xfs.py create gp.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gp.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gp.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gp.img gp_probe.bin --name /bin/gp.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    gp.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

printf 'B\rrun /bin/gp.bin\r' > gp.in

# ---- MODE A: graphics present (no -ng) --------------------------------------
../p8xemu -N -i gp.in -c gp.img -l 400000000 eeprom.bin > gpA.out 2>/dev/null || true
A=$(tr -d '\0\r' < gpA.out)
echo "$A" | grep -q "GRAPHICS AVAILABLE" || fail "mode A: monitor did not print GRAPHICS AVAILABLE"
echo "$A" | grep -q "NO GRAPHICS"        && fail "mode A: monitor wrongly printed NO GRAPHICS"
echo "$A" | grep -q "HAS=1" || fail "mode A: has_graphics() did not read GFXPRES=1 (OS re-affirm?)"
echo "$A" | grep -q "GPR=1" || fail "mode A: gpresent() returned 0 with graphics present"

# ---- MODE B: headless (-ng floats GLID to \$FF) -----------------------------
../p8xemu -ng -N -i gp.in -c gp.img -l 400000000 eeprom.bin > gpB.out 2>/dev/null || true
B=$(tr -d '\0\r' < gpB.out)
echo "$B" | grep -q "NO GRAPHICS"        || fail "mode B: monitor did not print NO GRAPHICS"
echo "$B" | grep -q "GRAPHICS AVAILABLE" && fail "mode B: monitor wrongly printed GRAPHICS AVAILABLE"
echo "$B" | grep -q "HAS=0" || fail "mode B: has_graphics() did not read GFXPRES=0"
echo "$B" | grep -q "?No display" || fail "mode B: gpresent()==0 did not take the ?No display exit"
echo "$B" | grep -q "GPR=1" && fail "mode B: reached the graphics path with no card"

echo "C-GFXPRES TEST: PASS (monitor probes+prints+sets GFXPRES; OS re-affirms; has_graphics/gpresent track the mode; GL program errors headless)"
