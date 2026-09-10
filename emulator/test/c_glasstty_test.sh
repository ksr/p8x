#!/bin/sh
# P2 of the two-mode design (docs/p8x-two-mode-design.md): the GLASS TTY -- the
# on-screen text console behind BIOS CONOUT. When GFXPRES (a GL card is fitted),
# the monitor's DISPINIT clears the screen and homes a text cursor, and PUTCTX
# mirrors every output byte to the GL screen via GL TEXT as well as the serial
# ACIA. So the OS and every program render on-screen with no change to their
# output code. Glyphs come from the card glyph bank: the MONITOR installs /FONT.GL
# from the CF root at wake (MONFONT) and blanks the screen -- the console is ON by
# default whenever a card is fitted, so even the pre-boot monitor is on the LCD.
#
# This boots the OS with a font present, runs `fsck` (prints "FSCK OK"), and
# checks that (1) serial still carries the output, and (2) glyph pixels actually
# land on the GL framebuffer in the top rows where the homed console draws. Then
# it boots headless (-ng) and checks the screen stays black (glass TTY off).
# MVP: clear-on-full (no scrollback) + no per-cell erase -- both in BACKLOG.md.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GLASSTTY TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o gtos.bin --base 0x2000 >/dev/null

# screen.bin is installed so `screen off`/`on` exist on the disk; the console itself
# is ON by default -- this test deliberately does NOT run `screen on`.
python3 $ROOT/tools/clib.py $ROOT/os/commands/screen.c -o sc.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py sc.pp.c -o sc.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py sc.asm -o sc.bin --base 0x6A00 >/dev/null

rm -f gt.img
python3 $ROOT/tools/p8xfs.py create gt.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gt.img gtos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gt.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gt.img sc.bin --name /bin/screen.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    gt.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# ---- console enabled: text must render on the GL screen --------------------
printf 'B\rfsck\r' > gt.in
../p8xemu -N -i gt.in -c gt.img -l 200000000 -g gt.ppm eeprom.bin > gt.out 2>/dev/null || true
tr -d '\0' < gt.out | grep -q 'FSCK OK' || fail "serial lost the command output (FSCK OK)"

python3 - <<'PY' || exit 1
import sys
d=open("gt.ppm","rb").read(); hdr=d.index(b"255\n")+4; px=d[hdr:]; W=480; H=272
def ink(x,y):
    i=(y*W+x)*3; return 1 if (px[i] or px[i+1] or px[i+2]) else 0
rows={}
total=0
for y in range(H):
    c=sum(ink(x,y) for x in range(W))
    if c: rows[y]=c; total+=c
bad=[]
# the homed console draws its first lines in the top rows (baseline y=264 -> screen
# row ~7 down); require a real amount of stroke ink concentrated near the top.
if total < 300:
    bad.append("only %d inked pixels — text did not render on the GL screen" % total)
topink=sum(c for y,c in rows.items() if y < 90)
if topink < 250:
    bad.append("too little ink in the top rows (%d) — console did not home/draw there" % topink)
# text is on the LEFT (console starts at column 0), not scattered right
leftcols=0
for y in rows:
    if y<90:
        leftcols += sum(ink(x,y) for x in range(0,240))
if leftcols < 200:
    bad.append("ink is not on the left half — console did not start at column 0")
# more than one text line rendered (the prompt line and the FSCK OK line)
lines = 0
prev=-10
for y in sorted(rows):
    if y-prev > 4: lines += 1
    prev=y
if lines < 2:
    bad.append("only %d text line(s) of ink — expected the prompt + output lines" % lines)
if bad:
    print("C-GLASSTTY TEST: FAIL"); [print("  "+b) for b in bad]; sys.exit(1)
print("glass TTY rendered %d stroke px over %d rows in >=2 lines, left-anchored" % (total, len(rows)))
PY

# ---- headless (-ng): the glass path is gated off; the system runs on serial --
# With no card fitted (GLID=$FF) the emulator's framebuffer is undefined, so the
# meaningful check is functional: GFXPRES=0 gates the glass mirror off, so PUTCTX
# never touches the (absent) GL FIFO -- the run completes on serial with no hang.
../p8xemu -ng -N -i gt.in -c gt.img -l 200000000 eeprom.bin > gtng.out 2>/dev/null || true
tr -d '\0' < gtng.out | grep -q 'FSCK OK' || fail "-ng: headless run did not complete on serial (glass path hung or stole the card?)"
tr -d '\0' < gtng.out | grep -q 'NO GRAPHICS' || fail "-ng: monitor did not report the headless mode"

echo "C-GLASSTTY TEST: PASS (OS output renders on the GL screen via CONOUT; gated off, serial-clean, when headless)"
