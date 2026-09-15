#!/bin/sh
# SCROLLBACK: the glass-TTY console is a hardware text OVERLAY now (firmware
# p8xmon.asm drives the card's TX* opcodes instead of drawing each glyph with
# GL stroke text). Its one user-visible upgrade over the old MVP is SCROLLBACK:
# when output reaches the bottom row, GTNL issues TXSCR (scroll the overlay up
# one row and blank the exposed bottom) instead of the old clear-on-full.
#
# This boots the OS and runs a program that prints 40 lines -- more than the
# 34-row screen holds. The DECISIVE difference from clear-on-full:
#   - SCROLLBACK: the screen stays FULL (~34 cell-rows inked) and the BOTTOM
#     row carries text (the most recent line scrolled up to it).
#   - clear-on-full (the old behaviour): at line 34 the screen clears and homes,
#     so only the ~6 lines printed since sit at the TOP and the bottom is BLANK.
# So: many inked rows AND an inked bottom band == scrollback.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-SCROLLBACK TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o sbos.bin --base 0x2000 >/dev/null

# a program that prints 40 wide lines -- past the 34-row screen, forcing scrolls
cat > sb_app.c <<'EOF'
int main() {
    int i;
    i = 0;
    while (i < 40) { puts("SCROLLBACKLINEMARKER"); i = i + 1; }
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py sb_app.c -o sb_app.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py sb_app.asm -o sb_app.bin --base 0x5900 >/dev/null

rm -f sb.img
python3 $ROOT/tools/p8xfs.py create sb.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   sb.img sbos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  sb.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    sb.img sb_app.bin --name /bin/sb.bin --load 0x5900 --exec 0x5900 >/dev/null
python3 $ROOT/tools/p8xfs.py put    sb.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

printf 'B\rrun /bin/sb.bin\r' > sb.in
../p8xemu -N -i sb.in -c sb.img -l 400000000 -g sb.ppm eeprom.bin > sb.out 2>/dev/null || true
# the program really ran on serial (its lines carry through CONOUT to the ACIA)
tr -d '\0' < sb.out | grep -q 'SCROLLBACKLINEMARKER' || fail "the program did not run (no serial output)"

python3 - <<'PY' || exit 1
import sys
d = open("sb.ppm","rb").read(); h = d.index(b"255\n")+4; px = d[h:]
W, H = 480, 272
def ink(x,y):
    i = (y*W+x)*3; return 1 if (px[i] or px[i+1] or px[i+2]) else 0
# count cell-rows (8px tall) that carry text
inked_rows = 0
for r in range(H//8):                       # 34 cell rows
    y0 = r*8
    if sum(ink(x,y) for y in range(y0, y0+8) for x in range(W)) > 20:
        inked_rows += 1
# the LOWER band (cell rows 25..31, screen y 200..255) must carry full lines of
# text: content scrolled DOWN to fill the whole screen. Clear-on-full prints its
# handful of post-clear lines at the TOP only, leaving this band blank. (The very
# bottom row holds just the returned shell's short prompt, so it is not the tell.)
lowband = sum(ink(x,y) for y in range(200,256) for x in range(W))
bad = []
if inked_rows < 25:
    bad.append("only %d cell-rows inked -- screen not full, looks like clear-on-full" % inked_rows)
if lowband < 500:
    bad.append("lower screen blank (%d px) -- content did not scroll down to fill it" % lowband)
if bad:
    print("C-SCROLLBACK TEST: FAIL"); [print("  "+b) for b in bad]; sys.exit(1)
print("console scrolled: %d/34 cell-rows inked, lower screen full (%d px)"
      % (inked_rows, lowband))
PY

echo "C-SCROLLBACK TEST: PASS (console overlay SCROLLS past the 34-row screen -- full screen, bottom row live -- not clear-on-full)"
