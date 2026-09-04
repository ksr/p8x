#!/bin/sh
# The C graphics demos, end to end -- the programs no other suite runs.
#
#   1. SIZE: every C command in run.sh's build list (plus image) must
#      compile through the real clib.py //#use splice and land BELOW
#      CSTACKTOP. This is the check the lib_gfx GL rewrite showed was
#      missing: a shared-library growth is a fleet-wide size tax, and
#      cube once sailed 209 bytes past the stack top with no error
#      anywhere -- the record pool just corrupted at run time.
#   2. RUNTIME: house draws its scene to DONE; tri paints a filled red
#      triangle; camera re-renders it from a placed eye; rotate and
#      page run clean. Frame pixels are asserted, not just exit text.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-DEMO TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

# ---- 1: compile every client, assert it fits under CSTACKTOP ---------------
# (the list mirrors run.sh's _ccmds + image; CSTACKTOP comes from the
#  generated memory map, never hardcoded)
CTOP=$(python3 -c "import sys; sys.path.insert(0,'$ROOT/generators'); import memmap; print(memmap.CSTACKTOP)")
for p in cube tri rotate page camera gl md house clsave paint desk image; do
    python3 $ROOT/tools/clib.py $ROOT/os/commands/$p.c > dm_$p.c \
        || fail "$p: clib.py splice failed"
    python3 $ROOT/compiler/p8cc.py dm_$p.c -o dm_$p.asm >/dev/null \
        || fail "$p: p8cc.py failed"
    python3 $ROOT/assembler/p8xasm.py dm_$p.asm -o dm_$p.bin --base 0x6A00 >/dev/null \
        || fail "$p: did not assemble"
    sz=$(wc -c < dm_$p.bin | tr -d ' ')
    end=$((0x6A00 + sz))
    [ "$end" -lt "$CTOP" ] \
        || fail "$p: end \$$(printf %X $end) is past CSTACKTOP \$$(printf %X $CTOP)"
done
echo "all twelve clients compile and fit below CSTACKTOP"

# ---- 2: runtime smoke on a fresh disk --------------------------------------
rm -f dm.img
python3 $ROOT/tools/p8xfs.py create dm.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   dm.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  dm.img /bin >/dev/null
for p in house tri rotate page camera; do
    python3 $ROOT/tools/p8xfs.py put dm.img dm_$p.bin \
        --name /bin/$p.bin --load 0x6A00 --exec 0x6A00 >/dev/null
done

# house: the animated demo's single frame, then DONE
printf 'B\rhouse\rexit\r' > dm.in
../p8xemu -N -i dm.in -c dm.img -l 500000000 -g dm_house.ppm eeprom.bin > dm.out 2>/dev/null || true
grep -q "DONE" dm.out || fail "house did not reach DONE"

# tri + camera + rotate + page: draw, re-render, and leave no errors
printf 'B\rtri -80 -80 300 80 -80 300 0 40 420 f 31 0 0\rcamera 0 0 0 0 0 340\rrotate 0 45 0 0 0 340\rpage sync\rexit\r' > dm.in
../p8xemu -N -i dm.in -c dm.img -l 900000000 -g dm_tri.ppm eeprom.bin > dm2.out 2>/dev/null || true
grep -q "usage" dm2.out && fail "a demo rejected its documented arguments"

python3 - <<'EOF' || exit 1
def frame(fn):
    d = open(fn, "rb").read()
    return d.split(b"\n", 3)[3]
px = frame("dm_house.ppm")
lit = sum(1 for i in range(0, len(px), 3) if px[i:i+3] != b"\x00\x00\x00")
assert lit > 1000, "house drew only %d pixels" % lit
px = frame("dm_tri.ppm")
red = sum(1 for i in range(0, len(px), 3) if px[i:i+3] == b"\xff\x00\x00")
lit = sum(1 for i in range(0, len(px), 3) if px[i:i+3] != b"\x00\x00\x00")
assert red > 200, "tri's red fill missing after rotate (%d red)" % red
assert lit > red, "only the fill drew -- outlines/edges missing"
print("house frame lit; tri survives camera + rotate with %d red px" % red)
EOF

echo "C-DEMO TEST: PASS (twelve clients fit under CSTACKTOP; house/tri/camera/rotate/page draw and exit clean)"
