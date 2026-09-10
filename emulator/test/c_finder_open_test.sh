#!/bin/sh
# P5 adapt Paint + Image to the Finder app frame:
#  - IMAGE: opening a .P8I in Finder launches `image <path>` (a new VIEW mode:
#    clear, draw the picture full-screen, wait for a key, return). Finder then
#    auto-returns via the launch script.
#  - PAINT: launched from the APPS menu ('a', P) it runs full-screen and, quitting
#    with 'q', RTS's to the shell -- so the Finder launch script re-launches the
#    desktop. No paint change was needed; this pins that it works.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-FINDER-OPEN TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o ios.bin --base 0x2000 >/dev/null
for c in finder image paint; do
    python3 $ROOT/tools/clib.py $ROOT/os/commands/$c.c -o $c.pp.c >/dev/null
    python3 $ROOT/compiler/p8cc.py $c.pp.c -o $c.a.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py $c.a.asm -o $c.a.bin --base 0x6A00 >/dev/null
done

python3 - <<'PY'
import struct
w,h=16,10
px=[0x001F]*(w*h)
px[0]=0xF800; px[w-1]=0x07E0; px[(h-1)*w]=0xFFFF; px[-1]=0xF81F
open("pic.p8i","wb").write(b"P8I"+bytes((1,))+struct.pack("<HH",w,h)+bytes((16,0))+struct.pack("<%dH"%(w*h),*px))
PY

rm -f i.img
python3 $ROOT/tools/p8xfs.py create i.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   i.img ios.bin >/dev/null
# AAA.P8I created FIRST at root so it is Finder's index 1 (right after "..")
python3 $ROOT/tools/p8xfs.py put    i.img pic.p8i --name /AAA.P8I >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  i.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    i.img finder.a.bin --name /bin/finder.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    i.img image.a.bin  --name /bin/image.bin  --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    i.img paint.a.bin  --name /bin/paint.bin  --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    i.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# ---- IMAGE via Finder: open the .p8i (DOWN to it, ENTER), any key, then q ----
# root list: ".." AAA.P8I bin FONT.GL  -> DOWN once selects AAA.P8I
printf 'B\rrun /bin/finder.bin\r\033[B\r q' > o.in
../p8xemu -N -i o.in -c i.img -l 400000000 -g o.ppm eeprom.bin > o.out 2>/dev/null || true
tr -d '\0' < o.out | grep -q 'run /bin/image.bin /AAA.P8I' || { echo "--- serial ---"; tr -d '\0'<o.out|tail; fail "opening the .p8i did not launch image with it"; }
# after the key, Finder is back (menu bar). (The image drew earlier; its return is
# proven by Finder redrawing.)
python3 - <<'PY' || exit 1
import sys
d=open("o.ppm","rb").read(); h=d.index(b"255\n")+4; px=d[h:]; W=480
def ink(x,y):
    i=(y*W+x)*3; return 1 if (px[i] or px[i+1] or px[i+2]) else 0
bar=sum(1 for y in range(1,12) for x in range(W) if ink(x,y))
if bar < W*8:
    print("C-FINDER-OPEN TEST: FAIL"); print("  Finder did not return after image (bar=%d)"%bar); sys.exit(1)
print("opened AAA.P8I in image; Finder auto-returned (bar=%d px)"%bar)
PY

# ---- PAINT via the APPS menu: 'a' P launches paint; 'q' returns to Finder ----
printf 'B\rrun /bin/finder.bin\raPqq' > p.in
../p8xemu -N -i p.in -c i.img -l 500000000 -g p.ppm eeprom.bin > p.out 2>/dev/null || true
tr -d '\0' < p.out | grep -q 'run /bin/paint.bin' || fail "APPS menu did not launch paint"
tr -d '\0' < p.out | grep -q 'PAINT' || fail "paint did not run (no PAINT banner)"
python3 - <<'PY' || exit 1
import sys
d=open("p.ppm","rb").read(); h=d.index(b"255\n")+4; px=d[h:]; W=480
def ink(x,y):
    i=(y*W+x)*3; return 1 if (px[i] or px[i+1] or px[i+2]) else 0
bar=sum(1 for y in range(1,12) for x in range(W) if ink(x,y))
if bar < W*8:
    print("C-FINDER-OPEN TEST: FAIL"); print("  Finder did not return after paint (bar=%d)"%bar); sys.exit(1)
print("launched paint from the APPS menu; q -> Finder auto-returned (bar=%d px)"%bar)
PY

echo "C-FINDER-OPEN TEST: PASS (Finder opens .p8i in image; APPS launches paint; both auto-return)"
