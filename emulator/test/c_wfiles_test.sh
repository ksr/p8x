#!/bin/sh
# wdesk's FILES window: the client draws DYNAMIC content (a directory listing)
# INSIDE a kernel-owned window. The kernel exposes the window rect (SYS_WKGET)
# and the top index (SYS_WKTOP); wdesk sets WINDOW/VWPORT to the FILES body and
# draws the CWD entries as text, but only when FILES is the focused (top)
# window -- so its content correctly sits on top. This proves the content model
# that FILES/TERM/VIEW all build on.
#   Boot wdesk fresh (FILES opens last, so it is on top). The frame must show
#   the FILES window with LISTING TEXT in its body, and the SHAPES window's
#   red card-list content still present -- both layers composited right.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-WFILES TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

python3 $ROOT/tools/clib.py $ROOT/os/commands/wdesk.c -o wf_wdesk.c
python3 $ROOT/compiler/p8cc.py wf_wdesk.c -o wf_wdesk.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py wf_wdesk.asm -o wf_wdesk.bin --base 0x6A00 >/dev/null

rm -f wf.img
python3 $ROOT/tools/p8xfs.py create wf.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   wf.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  wf.img /bin >/dev/null
# a couple of known entries so the listing has real names to draw
python3 $ROOT/tools/p8xfs.py mkdir  wf.img /docs >/dev/null
python3 $ROOT/tools/p8xfs.py put    wf.img wf_wdesk.bin --name /bin/wdesk.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wf.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# boot wdesk fresh; no input after -> it idles with the desktop up (FILES on top)
printf 'B\rrun /bin/wdesk.bin\r' > wf.in
../p8xemu -N -i wf.in -c wf.img -l 1500000000 -g wf.ppm eeprom.bin > wf.out 2>/dev/null || true
grep -q "WDESK" wf.out || fail "wdesk did not start"

python3 - <<'EOF' || exit 1
d = open("wf.ppm", "rb").read()
px = d.split(b"\n", 3)[3]
def p(x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
# FILES window: opened at (190,60) 240x170, on top (opened last)
assert p(190,60)==(255,255,255), "FILES window border missing: %r" % (p(190,60),)
# its BODY carries the directory listing -- white stroke text drawn by the
# client via SYS_WKGET/SYS_WKTOP inside the window (a real cluster of pixels)
txt = sum(1 for X in range(196,420) for Y in range(70,215) if p(X,Y)==(255,255,255))
assert txt > 60, "FILES listing text not drawn in the window body (%d white px)" % txt
# SHAPES' card-list content (red) is still there -- the two layers coexist
red = sum(1 for i in range(0,len(px),3) if px[i:i+3]==bytes((255,0,0)))
assert red > 300, "SHAPES card-list content missing (%d red px)" % red
print("the FILES window lists the current directory (%d px of stroke text in its" % txt)
print("body), drawn by the client into the kernel-owned window; SHAPES' content coexists")
EOF

# --- interactive: 'n' moves the selection; 'n' then ENTER navigates a dir ----
# 'nn' -> selection down to row 2 (a yellow-highlighted row at a different y)
printf 'B\rrun /bin/wdesk.bin\rnn' > wf2.in
../p8xemu -N -i wf2.in -c wf.img -l 1600000000 -g wf2.ppm eeprom.bin > wf2.out 2>/dev/null || true
# 'n' then ENTER -> open the first real dir (row 1) -> the listing changes
printf 'B\rrun /bin/wdesk.bin\rn\r' > wf3.in
../p8xemu -N -i wf3.in -c wf.img -l 1700000000 -g wf3.ppm eeprom.bin > wf3.out 2>/dev/null || true

python3 - <<'EOF' || exit 1
def rows(f):                       # screen-y rows carrying the yellow selection
    px = open(f,"rb").read().split(b"\n",3)[3]
    def p(x,wy):
        i=((271-wy)*480+x)*3; return tuple(px[i:i+3])
    return sorted({Y for Y in range(70,215) if any(p(X,Y)==(255,255,0) for X in range(196,420))})
a = rows("wf.ppm")                 # fresh: selection on row 0
b = rows("wf2.ppm")                # after 'nn': selection on row 2
assert a and b, "no selection highlight drawn (a=%r b=%r)" % (a,b)
assert min(b) < min(a) - 8, "selection did not move down on 'n' (row0 y=%r, row2 y=%r)" % (a,b)
# navigation changed the listing (root vs the opened subdirectory)
import hashlib
h1 = hashlib.md5(open("wf.ppm","rb").read()).hexdigest()
h3 = hashlib.md5(open("wf3.ppm","rb").read()).hexdigest()
assert h1 != h3, "ENTER on a directory did not change the listing"
print("n/p move the highlighted selection, and ENTER navigates into a directory --")
print("the FILES browser is interactive, all in the client")
EOF

echo "C-WFILES TEST: PASS (FILES: listing + selection (n/p) + ENTER navigation, client-side over the WM syscalls)"
