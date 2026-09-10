#!/bin/sh
# P4 Apps menu: press 'a' in the Finder desktop for a dropdown of the apps; a
# letter launches one (full-screen, auto-returning). Reuses the launch chain.
#
# Checks: 'a' draws the dropdown panel; 'a' then 'C' launches /bin/cube.bin (a
# stub here that prints CUBERAN and returns), and Finder auto-returns + redraws.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-FINDER-APPS TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o aos.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/finder.c -o fnd.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py fnd.pp.c -o fnd.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py fnd.asm -o fnd.bin --base 0x6A00 >/dev/null

# a stub standing in for /bin/cube.bin (the menu's C entry)
cat > c_stub.c <<'EOF'
int main() { puts("CUBERAN"); return 0; }
EOF
python3 $ROOT/compiler/p8cc.py c_stub.c -o c_stub.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py c_stub.asm -o c_stub.bin --base 0x6A00 >/dev/null

rm -f a.img
python3 $ROOT/tools/p8xfs.py create a.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   a.img aos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  a.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    a.img fnd.bin --name /bin/finder.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    a.img c_stub.bin --name /bin/cube.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    a.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# run 1: open finder, press 'a' -> the dropdown (getkey then blocks; grab it)
printf 'B\rrun /bin/finder.bin\ra' > a1.in
../p8xemu -N -i a1.in -c a.img -l 300000000 -g a1.ppm eeprom.bin > a1.out 2>/dev/null || true
python3 - <<'PY' || exit 1
import sys
d=open("a1.ppm","rb").read(); h=d.index(b"255\n")+4; px=d[h:]; W=480
def ink(x,y):
    i=(y*W+x)*3; return 1 if (px[i] or px[i+1] or px[i+2]) else 0
# panel: GL fillrect(58,138,250,256) -> screen rows ~16..133, cols 58..250
panel=sum(1 for y in range(16,133) for x in range(58,250) if ink(x,y))
if panel < 5000:
    print("C-FINDER-APPS TEST: FAIL"); print("  the APPS dropdown did not draw (%d px)"%panel); sys.exit(1)
print("APPS dropdown drew (%d px)"%panel)
PY

# run 2: open finder, 'a' (menu), 'C' (launch cube), then q (quit re-launched finder)
printf 'B\rrun /bin/finder.bin\raCq' > a2.in
../p8xemu -N -i a2.in -c a.img -l 400000000 -g a2.ppm eeprom.bin > a2.out 2>/dev/null || true
tr -d '\0' < a2.out | grep -q 'CUBERAN' || { echo "--- serial ---"; tr -d '\0' < a2.out | tail; fail "the APPS menu did not launch the app (no CUBERAN)"; }
tr -d '\0' < a2.out | grep -q 'run /bin/cube.bin' || fail "the launch script did not target /bin/cube.bin"
python3 - <<'PY' || exit 1
import sys
d=open("a2.ppm","rb").read(); h=d.index(b"255\n")+4; px=d[h:]; W=480
def ink(x,y):
    i=(y*W+x)*3; return 1 if (px[i] or px[i+1] or px[i+2]) else 0
bar=sum(1 for y in range(1,12) for x in range(W) if ink(x,y))
if bar < W*8:
    print("C-FINDER-APPS TEST: FAIL"); print("  Finder did not re-draw after the app (bar=%d)"%bar); sys.exit(1)
print("app launched from the menu (CUBERAN), Finder auto-returned (bar=%d px)"%bar)
PY

echo "C-FINDER-APPS TEST: PASS (APPS menu draws + launches an app + auto-returns)"
