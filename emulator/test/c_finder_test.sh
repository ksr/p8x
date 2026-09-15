#!/bin/sh
# P4 of the two-mode design (docs/p8x-two-mode-design.md): the FINDER desktop --
# a full-screen file browser (no tiling). A white menu bar across the top, the
# current directory as an ICON GRID below (5 columns), keyboard- and mouse-driven:
# arrows move the selection (RIGHT = +1 within a row, DOWN = +1 row), ENTER opens
# (a dir navigates in, a .BIN launches full-screen), Backspace goes up, q quits.
#
# Checks: the desktop RENDERS (white menu bar with black label text, an icon grid),
# and RIGHT-arrow moves the bright-blue selection highlight to the next column.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-FINDER TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o fos.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/finder.c -o fnd.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py fnd.pp.c -o fnd.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py fnd.asm -o fnd.bin --base 0x5900 >/dev/null

rm -f fnd.img
python3 $ROOT/tools/p8xfs.py create fnd.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   fnd.img fos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  fnd.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    fnd.img fnd.bin --name /bin/finder.bin --load 0x5900 --exec 0x5900 >/dev/null
python3 $ROOT/tools/p8xfs.py put    fnd.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  fnd.img /APPS >/dev/null
printf 'hi' > f_tmp.dat
python3 $ROOT/tools/p8xfs.py put    fnd.img f_tmp.dat --name /README.TXT >/dev/null

# run 1: draw, then quit
printf 'B\rrun /bin/finder.bin\rq' > f1.in
../p8xemu -N -i f1.in -c fnd.img -l 300000000 -g f1.ppm eeprom.bin > f1.out 2>/dev/null || true
# run 2: draw, RIGHT arrow (ESC [ C -> lib_ptr 130), then quit
printf 'B\rrun /bin/finder.bin\r\033[Cq' > f2.in
../p8xemu -N -i f2.in -c fnd.img -l 300000000 -g f2.ppm eeprom.bin > f2.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
def load(f):
    d=open(f,"rb").read(); h=d.index(b"255\n")+4; return d[h:]
W=480
def ink(px,x,y):
    i=(y*W+x)*3; return 1 if (px[i] or px[i+1] or px[i+2]) else 0
def hicx(px):   # selection = a bright-blue highlight box ~(49,73,231). x-centroid, -1 if none.
    xs=[x for y in range(15,120) for x in range(0,W)
        if (lambda i: px[i]<90 and 40<px[i+1]<110 and px[i+2]>150)((y*W+x)*3)]
    return sum(xs)//len(xs) if xs else -1
a=load("f1.ppm"); bad=[]
# menu bar = GL y 258..271 -> screen rows 0..13 (y-up flip). Must be a white strip
# with BLACK label text inside it.
barwhite=sum(1 for y in range(1,12) for x in range(W) if ink(a,x,y))
if barwhite < W*8:  bad.append("menu bar not a solid strip (%d white px)" % barwhite)
bartext=sum(1 for y in range(2,11) for x in range(4,320) if ink(a,x,y)==0)
if bartext < 40:    bad.append("no label text in the menu bar (%d black px)" % bartext)
# a file list drew below the bar (screen rows 18..266)
listink=sum(1 for y in range(18,266) for x in range(W) if ink(a,x,y))
if listink < 300:   bad.append("no file list (%d ink px)" % listink)
# selection = a bright-blue highlight box on the selected cell. RIGHT moves it to
# the next column, so its x-centroid must increase from run 1 to run 2.
x1=hicx(a); x2=hicx(load("f2.ppm"))
if x1<0: bad.append("no selection highlight in run 1")
elif x2<0: bad.append("no selection highlight in run 2")
elif x2 <= x1: bad.append("RIGHT did not move the selection (col x %d -> %d)" % (x1,x2))
if bad:
    print("C-FINDER TEST: FAIL"); [print("  "+b) for b in bad]; sys.exit(1)
print("finder: menu bar (%d white, %d text px) + icon grid (%d px); RIGHT moved the"
      " selection x %d -> %d" % (barwhite,bartext,listink,x1,x2))
PY

echo "C-FINDER TEST: PASS (full-screen Finder: menu bar + icon grid render; RIGHT navigates)"
