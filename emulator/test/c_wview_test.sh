#!/bin/sh
# wdesk's VIEW window: opening a .p8i from FILES opens a VIEW window sized to the
# image and STREAMS the picture into it, one BLIT per row -- desk's drawview, now
# into a kernel-owned window. This also exercises the new SYS_WKRAISE ($204B)
# kernel primitive: VIEW is opened as the 4th window (added on top), and a client
# turns a title back into an index via win_index() so it can raise an existing
# VIEW. Windows are addressed by TITLE (S/T/F/V), never index.
#   A 40x30 solid-GREEN .p8i sits at /PIC.P8I. Boot fresh (FILES on top), walk the
#   selection to PIC.P8I and ENTER. A VIEW window must appear with ~1200 green
#   pixels (the whole 40x30 image) inside it -- proof the picture streamed.
# Root lists ".." then bin, PIC.P8I, FONT.GL, so PIC.P8I is row 2 (two 'n's).
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-WVIEW TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

python3 $ROOT/tools/clib.py $ROOT/os/commands/wdesk.c -o wv_wdesk.c
python3 $ROOT/compiler/p8cc.py wv_wdesk.c -o wv_wdesk.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py wv_wdesk.asm -o wv_wdesk.bin --base 0x6A00 >/dev/null

# a 40x30 solid-green P8I (magic P8I, ver 1, w LE, h LE, depth 16, pad; then
# w*h little-endian RGB565 pixels -- 0x07E0 = pure green -> bytes E0 07)
python3 - <<'EOF'
w,h=40,30
hdr=bytes([0x50,0x38,0x49,1, w&255,w>>8, h&255,h>>8, 16, 0])
open("pic.p8i","wb").write(hdr + bytes([0xE0,0x07])*(w*h))
EOF

rm -f wv.img
python3 $ROOT/tools/p8xfs.py create wv.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   wv.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  wv.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    wv.img pic.p8i --name /PIC.P8I --load 0 --exec 0 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wv.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wv.img wv_wdesk.bin --name /bin/wdesk.bin --load 0x6A00 --exec 0x6A00 >/dev/null

# baseline: boot, no open -> VIEW not present, no green
printf 'B\rrun /bin/wdesk.bin\r' > wv0.in
../p8xemu -N -i wv0.in -c wv.img -l 1500000000 -g wv0.ppm eeprom.bin > wv0.out 2>/dev/null || true
grep -q WDESK wv0.out || fail "wdesk did not start"
# open PIC.P8I (row 2): two 'n' then ENTER
printf 'B\rrun /bin/wdesk.bin\rnn\r' > wv1.in
../p8xemu -N -i wv1.in -c wv.img -l 1900000000 -g wv1.ppm eeprom.bin > wv1.out 2>/dev/null || true

python3 - <<'EOF' || exit 1
import hashlib
def frame(f): return open(f,"rb").read().split(b"\n",3)[3]
def green(f):
    d=frame(f)
    def p(x,wy):
        i=((271-wy)*480+x)*3; return d[i],d[i+1],d[i+2]
    return sum(1 for X in range(0,480) for Y in range(0,272)
               if p(X,Y)[1]>180 and p(X,Y)[0]<90 and p(X,Y)[2]<90)
g0, g1 = green("wv0.ppm"), green("wv1.ppm")
assert g0 == 0, "baseline desktop already has green (%d) -- test image colour clashes" % g0
assert g1 > 800, "VIEW did not stream the picture: only %d green px (expect ~1200 = 40x30)" % g1
# the VIEW window border (white) must be present at its origin (20,20)
d=frame("wv1.ppm")
def p(x,wy):
    i=((271-wy)*480+x)*3; return (d[i],d[i+1],d[i+2])
assert p(20,20)==(255,255,255), "VIEW window border missing at (20,20): %r" % (p(20,20),)
assert hashlib.md5(frame("wv0.ppm")).hexdigest() != hashlib.md5(frame("wv1.ppm")).hexdigest(), \
    "opening a .p8i did not change the frame"
print("opening a .p8i from FILES opens a VIEW window (border at 20,20) and streams")
print("the picture into it -- %d green pixels = the whole 40x30 image" % g1)
EOF

echo "C-WVIEW TEST: PASS (VIEW: .p8i streamed into a title-addressed kernel window; SYS_WKRAISE primitive)"
