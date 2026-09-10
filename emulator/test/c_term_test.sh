#!/bin/sh
# P5 Term app: an on-screen console in the app frame. It enables the glass TTY
# (P2), and each typed command runs with its output ON THE GL SCREEN; Term
# persists by re-launching itself in continue mode after each command (no
# run-and-return syscall exists). `exit` returns to the Finder desktop.
#
# Checks: a command typed in Term runs and its output renders on screen (glass
# console); the "/TERM.RUN" chain targets the command + a `-c` re-launch; and
# `exit` hands off to /bin/finder.bin (its menu bar appears).
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-TERM TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o tos.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/term.c   -o tm.pp.c  >/dev/null
python3 $ROOT/compiler/p8cc.py tm.pp.c  -o tm.asm  >/dev/null
python3 $ROOT/assembler/p8xasm.py tm.asm  -o tm.bin  --base 0x6A00 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/finder.c -o fnd.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py fnd.pp.c -o fnd.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py fnd.asm -o fnd.bin --base 0x6A00 >/dev/null

rm -f t.img
python3 $ROOT/tools/p8xfs.py create t.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   t.img tos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  t.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    t.img tm.bin  --name /bin/term.bin   --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    t.img fnd.bin --name /bin/finder.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    t.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# run a command in Term: its output on screen, and Term re-launches (-c)
printf 'B\rrun /bin/term.bin\rfsck\r' > t.in
../p8xemu -N -i t.in -c t.img -l 400000000 -g t.ppm eeprom.bin > t.out 2>/dev/null || true
S=$(tr -d '\0' < t.out)
echo "$S" | grep -q 'term> fsck' || fail "the command was not echoed at the term prompt"
echo "$S" | grep -q 'FSCK OK'    || fail "the command did not run (no FSCK OK)"
# the re-launch chain
python3 $ROOT/tools/p8xfs.py get t.img /TERM.RUN --out trun.dat >/dev/null 2>&1 || fail "Term did not write its /TERM.RUN chain"
grep -q 'run /bin/term.bin -c' trun.dat || fail "/TERM.RUN does not re-launch Term in continue mode"
# the session rendered on the GL screen (glass console)
python3 - <<'PY' || exit 1
import sys
d=open("t.ppm","rb").read(); h=d.index(b"255\n")+4; px=d[h:]; W=480
ink=sum(1 for i in range(0,len(px),3) if px[i] or px[i+1] or px[i+2])
if ink < 500:
    print("C-TERM TEST: FAIL"); print("  the term session did not render on screen (%d ink)"%ink); sys.exit(1)
print("term session rendered on the GL screen (%d ink px)"%ink)
PY

# exit -> Finder
printf 'B\rrun /bin/term.bin\rexit\r' > te.in
../p8xemu -N -i te.in -c t.img -l 400000000 -g te.ppm eeprom.bin > te.out 2>/dev/null || true
python3 - <<'PY' || exit 1
import sys
d=open("te.ppm","rb").read(); h=d.index(b"255\n")+4; px=d[h:]; W=480
def ink(x,y):
    i=(y*W+x)*3; return 1 if (px[i] or px[i+1] or px[i+2]) else 0
bar=sum(1 for y in range(1,12) for x in range(W) if ink(x,y))
if bar < W*8:
    print("C-TERM TEST: FAIL"); print("  exit did not hand off to Finder (bar=%d)"%bar); sys.exit(1)
print("exit -> Finder desktop (menu bar %d px)"%bar)
PY

echo "C-TERM TEST: PASS (on-screen shell: command runs + renders; re-launch chain; exit -> Finder)"
