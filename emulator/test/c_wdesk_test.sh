#!/bin/sh
# wdesk: the desktop on the RESIDENT kernel, end to end -- the payoff rung.
#   wdesk opens two windows (SHAPES with card-list content) and enters the
#   kernel's SYS_WKRUN loop. 'l' makes the kernel SYS_EXEC paint OVER wdesk
#   (launch target set via SYS_WKPATH: "/bin/paint.bin -w"). 'q' quits paint,
#   which -- launched with -w -- calls SYS_WKRUN to resume the desktop. ^D
#   then leaves for the shell. The final frame must be the DESKTOP again, both
#   windows and the SHAPES content intact, even though the program that
#   created them (wdesk) was destroyed by the launch: the records live in the
#   OS and the picture lives on the card. This is what `desk` cannot do.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-WDESK TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

for p in wdesk paint; do
    python3 $ROOT/tools/clib.py $ROOT/os/commands/$p.c -o wd_$p.c
    python3 $ROOT/compiler/p8cc.py wd_$p.c -o wd_$p.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py wd_$p.asm -o wd_$p.bin --base 0x6A00 >/dev/null
done

rm -f wd.img
python3 $ROOT/tools/p8xfs.py create wd.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   wd.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  wd.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    wd.img wd_wdesk.bin --name /bin/wdesk.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wd.img wd_paint.bin --name /bin/paint.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wd.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# wdesk -> 'l' (kernel launches paint -w over wdesk) -> 'q' (paint quits and
# resumes the desktop via SYS_WKRUN) -> ^D (leave to the shell; the frame is
# dumped at the shell, never the monitor -- its wake-up blanks the screen)
# wdesk (menu bar + SYS_WKEVENT loop); 'l' from the menu launches paint OVER
# wdesk; 'q' quits paint, which -- launched with -w -- re-execs "wdesk -r",
# resuming the SAME resident windows AND the menu bar. No trailing ^D: the
# frame is dumped with the RESUMED desktop up (dumping after a quit-to-shell
# would catch the monitor's blanked console, not the desktop).
printf 'B\rrun /bin/wdesk.bin\rlq' > wd.in
../p8xemu -N -i wd.in -c wd.img -l 3000000000 -g wd.ppm eeprom.bin > wd.out 2>/dev/null || true

# WDESK (fresh) ... PAINT (launched) ... WDESK (resumed via -r) proves the
# desktop CLIENT -- not the kernel's bare loop -- came back after the launch.
seq=$(tr -d '\0' < wd.out | grep -oE "WDESK|PAINT" | tr '\n' ' ')
case "$seq" in *"WDESK "*"PAINT "*"WDESK"*) ;; *) fail "launch sequence was '$seq', want WDESK ... PAINT ... WDESK (resume)";; esac

python3 - <<'EOF' || exit 1
d = open("wd.ppm", "rb").read()
px = d.split(b"\n", 3)[3]
def p(x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
GREY = (49, 48, 74)
# the RESUMED desktop (wdesk -r), drawn by the resident kernel + this client:
assert p(40,40)==(255,255,255),   "SHAPES border gone after the launch/resume: %r" % (p(40,40),)
assert p(190,90)==(255,255,255),  "NOTES window gone after the launch/resume: %r" % (p(190,90),)
assert p(460,20)==GREY,           "desktop backdrop missing: %r" % (p(460,20),)
# SHAPES' card-list content (a red frame) survived on the card
red = sum(1 for i in range(0,len(px),3) if px[i:i+3]==bytes((255,0,0)))
assert red > 300, "SHAPES card-list content missing after resume (%d red px)" % red
# THE MENU BAR (drawn by the CLIENT, not the kernel): a white strip across the
# top rows with black text. It must be redrawn on resume.
assert p(460,265)==(255,255,255), "menu bar background not white at top-right: %r" % (p(460,265),)
bartext = sum(1 for X in range(8,240) for Y in range(259,268) if p(X,Y)==(0,0,0))
assert bartext > 30, "menu bar text not drawn (%d black px in the bar)" % bartext
print("wdesk drew its own MENU BAR and drove the kernel via SYS_WKEVENT; after")
print("launching paint and quitting it, 'wdesk -r' resumed -- windows, content")
print("AND the menu bar all back. The rich UI lives in the client, the OS stays tight.")
EOF

echo "C-WDESK TEST: PASS (client menu bar over SYS_WKEVENT; launch + resume the client, windows intact)"
