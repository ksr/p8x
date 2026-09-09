#!/bin/sh
# 15c-ii: wdesk's TERM renders a real command's OUTPUT in the window. Type a
# command and ENTER: wdesk arms the OUTCH->window sink at the TERM window (card
# list 31), writes a "<cmd>\nrun /bin/wdesk.bin -o" script, and hands it to the
# shell (SYS_RUNSH). The command runs with its stdout recorded into list 31;
# `wdesk -o` disarms and repaints, so the output appears in the window. The
# whole per-window-output feature, end to end, in the actual desktop.
#   Boot into /WTERM (mkdir+cd), launch wdesk, TAB TAB to focus TERM, run `pwd`.
#   pwd prints the CWD -- "/WTERM" must render in the TERM window.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-WTERMOUT TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

build() { python3 $ROOT/tools/clib.py "$1" -o t.pp.c && python3 $ROOT/compiler/p8cc.py t.pp.c -o t.asm >/dev/null && python3 $ROOT/assembler/p8xasm.py t.asm -o "$2" --base 0x6A00 >/dev/null; }
build $ROOT/os/commands/wdesk.c wto_wd.bin
build $ROOT/os/commands/pwd.c   wto_pwd.bin

rm -f wto.img
python3 $ROOT/tools/p8xfs.py create wto.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   wto.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  wto.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    wto.img wto_wd.bin  --name /bin/wdesk.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wto.img wto_pwd.bin --name /bin/pwd.bin   --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wto.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# A: focus TERM, no command. B: focus TERM, run `pwd`.
printf 'B\rmkdir WTERM\rcd WTERM\rrun /bin/wdesk.bin\r\t\t'     > a.in
printf 'B\rmkdir WTERM\rcd WTERM\rrun /bin/wdesk.bin\r\t\tpwd\r' > b.in
../p8xemu -N -i a.in -c wto.img -l 1500000000 -g a.ppm eeprom.bin > a.out 2>/dev/null || true
python3 $ROOT/tools/p8xfs.py create wtob.img >/dev/null   # fresh disk (A created WTERM already)
python3 $ROOT/tools/p8xfs.py boot   wtob.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  wtob.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    wtob.img wto_wd.bin  --name /bin/wdesk.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wtob.img wto_pwd.bin --name /bin/pwd.bin   --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wtob.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null
../p8xemu -N -i b.in -c wtob.img -l 1500000000 -g b.ppm eeprom.bin > b.out 2>/dev/null || true
grep -q "WDESK" b.out || fail "wdesk did not start"

python3 - <<'EOF' || exit 1
def body_text(f):
    d=open(f,"rb").read().split(b"\n",3)[3]
    def p(x,wy):
        i=((271-wy)*480+x)*3; return (d[i],d[i+1],d[i+2])
    # TERM window (70,100,300,150). Count white STROKE text (rows carrying a few
    # tens of white px -- not the ~300px chrome runs) in the output band below
    # the title bar, above the input line.
    n=0
    for wy in range(200,240):
        c=sum(1 for X in range(76,362) if p(X,wy)==(255,255,255))
        if 2<=c<=90: n=n+c
    return n
a=body_text("a.ppm"); b=body_text("b.ppm")
assert b > a + 40, "pwd output did not render in TERM (empty=%d px, with-pwd=%d px)" % (a,b)
print("typing `pwd` in wdesk's TERM ran it and rendered its output (/WTERM) in the")
print("window via the sink + script-chain: TERM body white text %d -> %d px" % (a,b))
EOF

echo "C-WTERMOUT TEST: PASS (wdesk TERM: a typed command's output renders in the window)"
