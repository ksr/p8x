#!/bin/sh
# P4 auto-return: launching an app from the Finder desktop must RETURN to the
# desktop when the app quits -- not drop to the shell. Finder does it with a
# script chain (no per-app flag): it writes "run <app>\nrun /bin/finder.bin <dir>"
# and hands it to the shell (SYS_RUNSH), so the app quitting (a plain return to
# the shell) flows on to the re-launch line.
#
# The disk's root has R.BIN FIRST (so Finder's initial selection is it): a trivial
# app that prints APPRAN and returns. Boot, run finder, ENTER (launch R.BIN), then
# q. If auto-return works: serial shows APPRAN (the app ran) AND the final screen
# is the Finder UI again (it re-launched), and it accepted the q.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-FINDER-RET TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o fos.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/finder.c -o fnd.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py fnd.pp.c -o fnd.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py fnd.asm -o fnd.bin --base 0x6A00 >/dev/null

# the trivial return-app
cat > r_app.c <<'EOF'
int main() { puts("APPRAN"); return 0; }
EOF
python3 $ROOT/compiler/p8cc.py r_app.c -o r_app.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py r_app.asm -o r_app.bin --base 0x6A00 >/dev/null

rm -f fr.img
python3 $ROOT/tools/p8xfs.py create fr.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   fr.img fos.bin >/dev/null
# R.BIN created FIRST -> it is Finder's first (selected) entry at root
python3 $ROOT/tools/p8xfs.py put    fr.img r_app.bin --name /R.BIN --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  fr.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    fr.img fnd.bin --name /bin/finder.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    fr.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# boot; run finder; DOWN (select R.BIN, index 1 after ".."); ENTER (launch it); q
printf 'B\rrun /bin/finder.bin\r\033[B\rq' > fr.in
../p8xemu -N -i fr.in -c fr.img -l 500000000 -g fr.ppm eeprom.bin > fr.out 2>/dev/null || true

# the app ran (launched via the script)
tr -d '\0' < fr.out | grep -q 'APPRAN' || { echo "--- serial ---"; tr -d '\0' < fr.out | tail; fail "the app did not run (no APPRAN) -- launch script failed"; }
# finder re-launched: its `run /bin/finder.bin /` line appears in the echoed script
tr -d '\0' < fr.out | grep -q 'run /bin/finder.bin /' || fail "the auto-return line did not run (finder was not re-launched)"

# and the final screen is the Finder UI again (menu bar white strip + file list)
python3 - <<'PY' || exit 1
import sys
d=open("fr.ppm","rb").read(); h=d.index(b"255\n")+4; px=d[h:]; W=480
def ink(x,y):
    i=(y*W+x)*3; return 1 if (px[i] or px[i+1] or px[i+2]) else 0
bar=sum(1 for y in range(1,12) for x in range(W) if ink(x,y))          # menu bar (GL top)
lst=sum(1 for y in range(18,266) for x in range(W) if ink(x,y))        # file list
if bar < W*8 or lst < 300:
    print("C-FINDER-RET TEST: FAIL"); print("  final screen is not the Finder UI (bar=%d list=%d)"%(bar,lst)); sys.exit(1)
print("app launched (APPRAN), Finder re-launched and redrew its UI (bar=%d list=%d px)"%(bar,lst))
PY

echo "C-FINDER-RET TEST: PASS (launch an app from Finder -> app runs -> auto-return to Finder)"
