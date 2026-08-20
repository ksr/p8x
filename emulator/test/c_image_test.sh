#!/bin/sh
# The `image` OS command (os/commands/image.c): view AND grab P8I pictures
# from the shell, no BASIC.
#
#   1. draw: a known 8x5 P8I drawn at (100,50) -- exact-pixel PPM asserts.
#   2. grab: `image read 100 50 107 54 /G.P8I` must produce a file
#      BYTE-IDENTICAL to the one that was drawn (P8I's self-describing
#      header is what makes draw/grab true inverses).
#   3. re-draw: the grab drawn again at (200,100) -- same pixels there.
#   4. errors: missing file -> ?No file; wrong magic -> ?NOT P8I; -h usage.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-IMAGE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

python3 $ROOT/tools/clib.py $ROOT/os/commands/image.c > ci_image.c
python3 $ROOT/compiler/p8cc.py ci_image.c -o ci_image.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py ci_image.asm -o ci_image.bin --base 0x6A00 >/dev/null

# a tiny P8I with distinct, bit-patterned colours (row-major, little-endian)
python3 - <<'EOF'
import struct
w, h = 8, 5
px = [((x * 37 + y * 91 + 5) * 257) & 0xFFFF for y in range(h) for x in range(w)]
data = b"P8I" + bytes([1]) + struct.pack("<HH", w, h) + bytes([0x10, 0])
data += b"".join(struct.pack("<H", p) for p in px)
open("ci_t.p8i", "wb").write(data)
EOF
printf 'not a picture\n' > ci_bad.txt

rm -f ci.img
python3 $ROOT/tools/p8xfs.py create ci.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ci.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ci.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    ci.img ci_image.bin --name /bin/image.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    ci.img ci_t.p8i --name /T.P8I --load 0 --exec 0 >/dev/null
python3 $ROOT/tools/p8xfs.py put    ci.img ci_bad.txt --name /T.TXT --load 0 --exec 0 >/dev/null

printf 'B\rimage 100 50 /T.P8I\rimage read 100 50 107 54 /G.P8I\rimage 200 100 /G.P8I\rimage 0 0 /NOPE.P8I\rimage 0 0 /T.TXT\rimage -h\r' > ci.in
../p8xemu -N -i ci.in -c ci.img -l 600000000 -g ci.ppm eeprom.bin > ci.out 2>/dev/null || true

grep -q '?No file'  ci.out || fail "missing file did not say ?No file"
grep -q '?NOT P8I'  ci.out || fail "bad magic did not say ?NOT P8I"
grep -q 'usage: IMAGE' ci.out || fail "-h did not print usage"

# 1+3: exact pixels at BOTH placements
python3 - <<'EOF' || exit 1
import struct
raw = open("ci_t.p8i","rb").read()
w, h = struct.unpack("<HH", raw[4:8])
pix = list(struct.unpack("<%dH" % (w*h), raw[10:]))
data = open("ci.ppm","rb").read()
hdr = data.split(b"\n",3); W, H = map(int, hdr[1].split()); px = hdr[3]
def expand(c):
    r5,g6,b5 = (c>>11)&31, (c>>5)&63, c&31
    return ((r5<<3)|(r5>>2), (g6<<2)|(g6>>4), (b5<<3)|(b5>>2))
for (ox, oy) in [(100,50), (200,100)]:
    for y in range(h):
        for x in range(w):
            o = ((oy+y)*W + ox+x)*3
            if tuple(px[o:o+3]) != expand(pix[y*w+x]):
                raise SystemExit("C-IMAGE: pixel (%d,%d) wrong at origin (%d,%d)"
                                 % (x, y, ox, oy))
print("draw + re-draw pixels exact at both placements")
EOF

# 2: the grab is byte-identical to the source
python3 $ROOT/tools/p8xfs.py get ci.img /G.P8I --out ci_g.p8i >/dev/null
cmp ci_t.p8i ci_g.p8i || fail "grab is not byte-identical to the drawn file"

echo "C-IMAGE TEST: PASS (draw, grab round-trip byte-identical, re-draw, errors, usage)"
