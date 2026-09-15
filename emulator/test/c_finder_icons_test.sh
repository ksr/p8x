#!/bin/sh
# The icon-grid Finder (two-mode P4, GUI pass): files/folders as icons in a
# 5-col grid, mouse SELECTION (left click) and a right-click CONTEXT MENU
# (open / rename / duplicate / move / delete; new folder on empty space).
#
# Drives the real pointer path (lib_ptr) with scripted xterm SGR mouse reports
# and checks the FILESYSTEM after each mouse-driven operation. A python helper
# maps a target panel point (window coords, y up) to the terminal cell an SGR
# report carries -- lib_ptr, with no size reply on a -i session, uses 80x24.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-FINDER-ICONS TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o ios.bin --base 0x2000 >/dev/null
build() {
    python3 $ROOT/tools/clib.py $ROOT/os/commands/$1.c -o $1.pp.c >/dev/null
    python3 $ROOT/compiler/p8cc.py $1.pp.c -o $1.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py $1.asm -o $1.bin --base 0x5900 >/dev/null
}
build finder; build del; build cp; build mv

# a disk whose root, after "..", holds exactly: BIN(dir) FONT.GL DOCS(dir)
# READ.TXT GAME.BIN -- so the grid is  row0: .. BIN FONT.GL DOCS READ.TXT
# (idx 0..4), row1: GAME.BIN (idx 5). Deterministic cell positions.
mkdisk() {
    rm -f i.img
    python3 $ROOT/tools/p8xfs.py create i.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   i.img ios.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  i.img /bin >/dev/null
    for c in finder del cp mv; do
        python3 $ROOT/tools/p8xfs.py put i.img $c.bin --name /bin/$c.bin --load 0x5900 --exec 0x5900 >/dev/null
    done
    python3 $ROOT/tools/p8xfs.py put   i.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir i.img /DOCS >/dev/null
    printf 'hello\n' > t.dat
    python3 $ROOT/tools/p8xfs.py put i.img t.dat --name /READ.TXT >/dev/null
    python3 $ROOT/tools/p8xfs.py put i.img t.dat --name /GAME.BIN --load 0x5900 --exec 0x5900 >/dev/null
}
ls_root() { python3 $ROOT/tools/p8xfs.py ls i.img / 2>/dev/null | awk '{print $1}'; }

# emit an SGR mouse report for a target PANEL point: btn 0=left 2=right, M press.
# cell = panel->cell for lib_ptr's 80x24 default (px/6+1 ; nearest row for y-up).
sgr() { python3 - "$@" <<'PY'
import sys
btn=int(sys.argv[1]); px=int(sys.argv[2]); py=int(sys.argv[3]); final=sys.argv[4]
cx=px//6+1
best=1;bd=999
for cy in range(1,25):
    p=271-((cy-1)*11+((cy-1)*8)//24)
    if abs(p-py)<bd: bd=abs(p-py); best=cy
sys.stdout.write("\033[<%d;%d;%d%s"%(btn,cx,best,final))
PY
}

# grid geometry (mirrors finder.c): col c center x = c*96+48 ; row r icon-mid y
CX0=48; CX1=144; CX2=240; CX3=336            # column centres
RY0=220; RY1=160                             # row0 / row1 icon-ish y (window, y up)

# ---- 1. right-click an item pops the context menu (pixel check) ------------
mkdisk
{ printf 'B\rrun /bin/finder.bin\r'; sgr 2 $CX0 $RY1 M; } > i.in   # RT-click READ.TXT? no: idx5 is row1 col0
# idx5 = GAME.BIN (row1 col0). Right-click it, grab the popup.
../p8xemu -N -i i.in -c i.img -l 300000000 -g ic1.ppm eeprom.bin >/dev/null 2>&1 || true
python3 - <<'PY' || exit 1
import sys
d=open("ic1.ppm","rb").read(); h=d.index(b"255\n")+4; px=d[h:]; W=480
def ink(x,y): i=(y*W+x)*3; return 1 if(px[i] or px[i+1] or px[i+2]) else 0
# the popup is a white box ~132 wide, 62 tall, near the click (panel ~48,158).
# scan a band below the click for a bright rectangle of menu text.
box=sum(1 for y in range(96,158) for x in range(48,180) if ink(x,y))
if box < 3000: print("C-FINDER-ICONS TEST: FAIL"); print("  context menu did not pop (%d px)"%box); sys.exit(1)
print("  right-click: context menu drew (%d px)"%box)
PY

# ---- 2. right-click -> DELETE -> confirm Y removes the file ----------------
mkdisk
{ printf 'B\rrun /bin/finder.bin\r'; sgr 2 $CX0 $RY1 M; sgr 0 60 101 M; printf 'y'; } > i.in
# right-click GAME.BIN (idx5) ; left-click the DELETE row (~panel 60,101) ; Y
../p8xemu -N -i i.in -c i.img -l 400000000 eeprom.bin > i.out 2>/dev/null || true
ls_root | grep -q '^GAME.BIN$' && { echo root:; ls_root; fail "right-click DELETE did not remove /GAME.BIN"; }
echo "  right-click DELETE + Y removed /GAME.BIN"

# ---- 3. right-click empty space -> NEW FOLDER -> type name ----------------
mkdisk
{ printf 'B\rrun /bin/finder.bin\r'; sgr 2 240 101 M; sgr 0 250 90 M; printf 'MADEHERE\r'; } > i.in
# right-click an empty cell (row2) ; click NEW FOLDER ; type the name
../p8xemu -N -i i.in -c i.img -l 400000000 eeprom.bin > i.out 2>/dev/null || true
ls_root | grep -q '^MADEHERE$' || { echo root:; ls_root; fail "empty right-click NEW FOLDER did not create /MADEHERE"; }
echo "  right-click empty -> NEW FOLDER /MADEHERE"

# ---- 4. right-click -> DUPLICATE -> type name copies the file -------------
mkdisk
{ printf 'B\rrun /bin/finder.bin\r'; sgr 2 $CX0 $RY1 M; sgr 0 60 124 M; printf 'GG.BIN\r'; } > i.in
# right-click GAME.BIN ; click DUPLICATE row (~panel 60,124) ; type new name
../p8xemu -N -i i.in -c i.img -l 400000000 eeprom.bin > i.out 2>/dev/null || true
ls_root | grep -q '^GG.BIN$'   || { echo root:; ls_root; fail "right-click DUPLICATE did not create /GG.BIN"; }
ls_root | grep -q '^GAME.BIN$' || fail "duplicate removed the original /GAME.BIN"
echo "  right-click DUPLICATE -> /GG.BIN (original intact)"

echo "C-FINDER-ICONS TEST: PASS (icon grid + mouse select + right-click menu: delete / new folder / duplicate)"
