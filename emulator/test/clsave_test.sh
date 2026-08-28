#!/bin/sh
# clsave (stage 10e's payoff): record a list on the card, save it to a
# file via CLRD, and verify the FILE holds exactly the list's hex bytes
# -- then replay the saved file and probe a pixel it draws. Scenes now
# survive power.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "CLSAVE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/clsave.c -o cs.c
python3 $ROOT/compiler/p8cc.py cs.c -o cs.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cs.asm -o cs.bin --base 0x6A00 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/gl.c -o csgl.c
python3 $ROOT/compiler/p8cc.py csgl.c -o csgl.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py csgl.asm -o csgl.bin --base 0x6A00 >/dev/null

rm -f cs.img
python3 $ROOT/tools/p8xfs.py create cs.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cs.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cs.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cs.img cs.bin  --name /bin/clsave.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    cs.img csgl.bin --name /bin/gl.bin --load 0x6A00 --exec 0x6A00 >/dev/null

# record a small list (a MOVE3+DRAW3 pair), save it, delete it from the
# card, replay the FILE, and probe. Window==viewport => screen coords.
# every line under GETLN's 63-char limit (the BACKLOG trap)
printf 'B\rgl VWPORT 0 479 0 271 WINDOW 0 479 0 271\rgl CLEARS 0 0 0 COLOR 31 0 0\rgl CLBEG 9 MOVE3 100 100 300\rgl DRAW3 200 100 300 CLEND\rclsave 9 /SAVED.GLB\rgl CLDEL 9\rgl /SAVED.GLB\r' > cs.in
../p8xemu -N -i cs.in -c cs.img -l 600000000 -g cs.ppm eeprom.bin > cs.out 2>/dev/null || true
tr -d '\0\r' < cs.out | grep -q "bytes saved" || fail "clsave did not report success"
tr -d '\0\r' < cs.out | grep -qi "error\|no such" && fail "unexpected error output"

python3 $ROOT/tools/p8xfs.py get cs.img /SAVED.GLB --out saved.glb >/dev/null
python3 - <<'EOF' || exit 1
d = open("saved.glb","rb").read()
# MOVE3 100 100 300 ; DRAW3 200 100 300, int16 LE
want = bytes([0x12,100,0,100,0,44,1, 0x2A,200,0,100,0,44,1])
assert d == want, "saved bytes differ: %s" % d.hex()
EOF
python3 - <<'EOF' || exit 1
d=open("cs.ppm","rb").read(); px=d.split(b"\n",3)[3]
# the replayed 3D line: z=300 native camera -> x,y scale by 256/300
# (100,100)->(85,85), (200,100)->(170,85); screen y = 271-85 = 186
i=(186*480+128)*3
assert px[i:i+3]==b"\xff\x00\x00", "replayed line pixel wrong: %r" % (px[i:i+3],)
EOF
echo "CLSAVE TEST: PASS (record -> save -> byte-exact file -> delete -> replay from disk -> pixel proof)"
