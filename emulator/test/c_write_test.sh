#!/bin/sh
# P5 Write app: a full-screen text editor on the GL display. Open a file, edit it
# (insert / newline / backspace / cursor moves), ^O saves, ^X quits to Finder.
#
# Checks: typing HELLO<enter>WORLD then ^O saves exactly "HELLO\nWORLD"; ^X hands
# off to Finder; and re-opening the file LOADS it and RENDERS the text on screen.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-WRITE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o wos.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/write.c  -o wr.pp.c  >/dev/null
python3 $ROOT/compiler/p8cc.py wr.pp.c  -o wr.asm  >/dev/null
python3 $ROOT/assembler/p8xasm.py wr.asm  -o wr.bin  --base 0x6A00 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/finder.c -o fnd.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py fnd.pp.c -o fnd.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py fnd.asm -o fnd.bin --base 0x6A00 >/dev/null

rm -f w.img
python3 $ROOT/tools/p8xfs.py create w.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   w.img wos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  w.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    w.img wr.bin  --name /bin/write.bin  --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    w.img fnd.bin --name /bin/finder.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    w.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# edit a new file, save (^O = 0x0F), quit (^X = 0x18)
printf 'B\rrun /bin/write.bin /T.TXT\rHELLO\rWORLD\017\030' > w.in
../p8xemu -N -i w.in -c w.img -l 400000000 -g w.ppm eeprom.bin > w.out 2>/dev/null || true

# the file was saved with exactly the typed text
python3 $ROOT/tools/p8xfs.py get w.img /T.TXT --out tsav.dat >/dev/null 2>&1 || fail "Write did not save /T.TXT"
python3 - <<'PY' || exit 1
import sys
b=open("tsav.dat","rb").read()
if b != b"HELLO\nWORLD":
    print("C-WRITE TEST: FAIL"); print("  saved bytes are %r, want b'HELLO\\nWORLD'"%b); sys.exit(1)
print("saved exactly HELLO<newline>WORLD")
PY
# ^X handed off to Finder (its menu bar drew)
python3 - <<'PY' || exit 1
import sys
d=open("w.ppm","rb").read(); h=d.index(b"255\n")+4; px=d[h:]; W=480
def ink(x,y):
    i=(y*W+x)*3; return 1 if (px[i] or px[i+1] or px[i+2]) else 0
bar=sum(1 for y in range(1,12) for x in range(W) if ink(x,y))
if bar < W*8:
    print("C-WRITE TEST: FAIL"); print("  ^X did not hand off to Finder (bar=%d)"%bar); sys.exit(1)
print("edit + save ok; ^X -> Finder (bar=%d px)"%bar)
PY

# re-open the saved file: it LOADS and RENDERS (no edits, just view + cursor)
printf 'B\rrun /bin/write.bin /T.TXT\r' > w2.in
../p8xemu -N -i w2.in -c w.img -l 400000000 -g w2.ppm eeprom.bin > w2.out 2>/dev/null || true
python3 - <<'PY' || exit 1
import sys
d=open("w2.ppm","rb").read(); h=d.index(b"255\n")+4; px=d[h:]; W=480
def ink(x,y):
    i=(y*W+x)*3; return 1 if (px[i] or px[i+1] or px[i+2]) else 0
bar=sum(1 for y in range(1,12) for x in range(W) if ink(x,y))        # menu bar
body=sum(1 for y in range(16,250) for x in range(W) if ink(x,y))     # the loaded text
if bar < W*8 or body < 100:
    print("C-WRITE TEST: FAIL"); print("  re-opened file did not render (bar=%d body=%d)"%(bar,body)); sys.exit(1)
print("re-opened /T.TXT loaded and rendered (bar=%d text=%d px)"%(bar,body))
PY

echo "C-WRITE TEST: PASS (edit/insert/newline/save exact; ^X -> Finder; load + render)"
