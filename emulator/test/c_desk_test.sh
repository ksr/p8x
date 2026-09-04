#!/bin/sh
# desk: the window system (rung 2 -- lib_wm), scripted end to end.
#   1. keyboard session: type into the focused TERM (card TEXT in
#      window-local coords), TAB raises SHAPES; focus renders as the
#      title-bar colour; SHAPES' content -- replayed from a CARD-
#      RESIDENT list (CLRUN, two wire bytes) -- still clips with ZERO
#      escaped pixels; the menu bar owns the top rows.
#   2. mouse drag: press TERM's title, drag, release -- the window
#      lands cell-exact and the vacated desktop repaints.
#   3. the MENU, the Mac way: press DESK, slide down, release on
#      QUIT -- the program exits without Ctrl-D.
#   4. the CLOSE BOX: one click removes TERM; SHAPES inherits focus.
#   5. the FILES browser: arrows walk the listing (FNEXT through
#      lib_dirent; '..' listed, '.', deleted slots and the volume
#      slot filtered), ENTER on a .P8I opens the VIEW window -- the
#      image BLITs from its file into window-local coords.
#   6. navigation: ENTER on a directory re-scans; a picture opened
#      from inside /PICS proves the whole path.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-DESK TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

python3 $ROOT/tools/clib.py $ROOT/os/commands/desk.c > cd_desk.c
python3 $ROOT/compiler/p8cc.py cd_desk.c -o cd_desk.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cd_desk.asm -o cd_desk.bin --base 0x6A00 >/dev/null

rm -f cd.img
python3 $ROOT/tools/p8xfs.py create cd.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cd.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cd.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cd.img cd_desk.bin --name /bin/desk.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    cd.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null
python3 - <<'EOF2'
import struct
def p8i(fn, w, h, color):
    hdr = b"P8I" + bytes([1]) + struct.pack("<HH", w, h) + bytes([16, 0])
    open(fn, "wb").write(hdr + struct.pack("<H", color) * (w * h))
p8i("cd_red.p8i", 4, 3, 0xF800)
p8i("cd_blue.p8i", 4, 3, 0x001F)
EOF2
python3 $ROOT/tools/p8xfs.py put    cd.img cd_red.p8i --name /T.P8I --load 0 --exec 0 >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cd.img /PICS >/dev/null
python3 $ROOT/tools/p8xfs.py put    cd.img cd_blue.p8i --name /PICS/B.P8I --load 0 --exec 0 >/dev/null

# 1: type HI + ENTER into TERM, TAB to raise SHAPES, quit
printf 'B\rdesk\rHI\r\011\004' > cd1.in
../p8xemu -N -i cd1.in -c cd.img -l 1200000000 -g cd1.ppm eeprom.bin > cd1.out 2>/dev/null || true
grep -q "bye" cd1.out || fail "keyboard session did not quit cleanly"

# 2: mouse -- press TERM's title (cell 51,5), drag, release at (31,5)
printf 'B\rdesk\r\033[<0;51;5M\033[<32;41;5M\033[<32;31;5M\033[<0;31;5m\004' > cd2.in
../p8xemu -N -i cd2.in -c cd.img -l 1200000000 -g cd2.ppm eeprom.bin > cd2.out 2>/dev/null || true
grep -q "bye" cd2.out || fail "mouse session did not quit cleanly"

# 3: the menu -- press DESK in the bar, slide to QUIT, release
printf 'B\rdesk\r\033[<0;5;1M\033[<32;5;3M\033[<32;5;5M\033[<32;5;6M\033[<0;5;6m' > cd3.in
../p8xemu -N -i cd3.in -c cd.img -l 1200000000 eeprom.bin > cd3.out 2>/dev/null || true
grep -q "bye" cd3.out || fail "menu QUIT did not exit the program"

# 4: the close box -- click it on TERM, then quit
printf 'B\rdesk\r\033[<0;34;5M\033[<0;34;5m\004' > cd4.in
../p8xemu -N -i cd4.in -c cd.img -l 1200000000 -g cd4.ppm eeprom.bin > cd4.out 2>/dev/null || true
grep -q "bye" cd4.out || fail "close-box session did not quit cleanly"

# 5: browse to /T.P8I (root lists .. bin FONT.GL T.P8I PICS) and open it
printf 'B\rdesk\r\011\011\033[B\033[B\033[B\r\004' > cd5.in
../p8xemu -N -i cd5.in -c cd.img -l 1500000000 -g cd5.ppm eeprom.bin > cd5.out 2>/dev/null || true
grep -q "bye" cd5.out || fail "browser session did not quit cleanly"

# 6: navigate into /PICS and open B.P8I there
printf 'B\rdesk\r\011\011\033[B\033[B\033[B\033[B\r\033[B\r\004' > cd6.in
../p8xemu -N -i cd6.in -c cd.img -l 1800000000 -g cd6.ppm eeprom.bin > cd6.out 2>/dev/null || true
grep -q "bye" cd6.out || fail "navigation session did not quit cleanly"

python3 - <<'EOF' || exit 1
def load(f):
    d = open(f, "rb").read()
    return d.split(b"\n", 3)[3]
def p(px, x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
DESK = (49, 48, 74)
a = load("cd1.ppm")
assert p(a,240,265)==(255,255,255), "menu bar missing"
bartext = sum(1 for X in range(6,60) for Y in range(259,271)
              if p(a,X,Y)==(0,0,0))
assert bartext > 5, "DESK menu title not drawn (%d px)" % bartext
assert p(a,10,250)==DESK,           "desktop backdrop missing"
assert p(a,60,182)==(255,255,255),  "SHAPES title not focused-white after TAB"
assert p(a,300,222)==(132,130,132), "TERM title not unfocused-grey"
assert p(a,60,51)==(255,0,0),       "list-replayed SHAPES border missing"
esc = 0
for X in range(0,480):
    for Y in range(0,258):
        if p(a,X,Y)==(255,255,0) and not (41<=X<=248 and 41<=Y<=175):
            esc += 1
assert esc == 0, "%d pixels ESCAPED the window clip (list replay)" % esc
green = sum(1 for X in range(195,425) for Y in range(95,215)
            if p(a,X,Y)==(0,255,0))
assert green > 10, "TERM text missing (%d green px)" % green
b = load("cd2.ppm")
assert p(b,80,222)==(255,255,255),  "dragged TERM title not at the new x"
assert p(b,70,150)==(255,255,255),  "dragged TERM left border missing"
assert p(b,309,150)==(255,255,255), "dragged TERM right border missing"
assert p(b,320,222)==DESK,          "vacated area did not repaint"
c = load("cd4.ppm")
assert p(c,250,222)==DESK,          "closed TERM still on screen"
assert p(c,400,232)==(255,255,255), "FILES did not inherit focus after close"
e = load("cd5.ppm")
assert p(e,22,22)==(255,0,0),       "opened T.P8I not drawn in the viewer"
assert p(e,24,21)==(255,0,0),       "viewer image incomplete"
f = load("cd6.ppm")
assert p(f,22,22)==(0,0,255),       "B.P8I via /PICS navigation not drawn"
print("menu, close box, card-list repaint, clip, drag, browser+viewer: pixel-exact")
EOF

echo "C-DESK TEST: PASS (lib_wm: menu, close boxes, card-list repaint, clip, drag; FILES browser + BLIT viewer)"
