#!/bin/sh
# The CLICKABLE menu bar: a mouse press in the top rows is handed to the
# client (SYS_WKEVENT event 2) with the cursor COLUMN in SYS_WKARG, so the
# client's menu bar can act on it -- the kernel owns only the windows below.
#   A client opens ONE window and loops over SYS_WKEVENT. On event 2 (a bar
#   click) it reads the column: a click in the CLOSE zone (cols 20..35) pops
#   the top window via SYS_WKCLOSE. We feed a mouse press+release at cell
#   (26,1) -- the top row, CLOSE zone -- and check the window is gone.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "WM-BARMENU TEST: FAIL — $1"; exit 1; }

WK_INIT=0x2027
WK_OPEN=0x202A
WK_PAINT=0x202D
WK_RUN=0x2030
WK_EVENT=0x203C
WK_CLOSE=0x203F
WK_ARG=0x2042

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > bm_run.c <<EOF
char param[22];
int setw(int x, int y, int w, int h, int list, char *t) {
    int i;
    param[0]=x&255; param[1]=(x/256)&255;
    param[2]=y&255; param[3]=(y/256)&255;
    param[4]=w&255; param[5]=(w/256)&255;
    param[6]=h&255; param[7]=(h/256)&255;
    param[8]=list;
    i=0; while (t[i] && i<12) { param[10+i]=t[i]; i=i+1; }
    param[9]=i;
    while (i<12) { param[10+i]=0; i=i+1; }
    bios($WK_OPEN, param, 0);
    return 0;
}
int main() {
    int e; int col; int going;
    bios($WK_INIT, 0, 0);
    setw(100, 100, 150, 100, 0, "WIN");
    bios($WK_PAINT, 0, 0);
    going = 1;
    while (going) {
        e = bios($WK_EVENT, 0, 0);
        if (e & 256) { going = 0; }
        else if (e == 2) {                        /* a menu-bar click */
            col = bios($WK_ARG, 0, 0);
            if (col >= 20 && col < 36) {           /* the CLOSE zone */
                bios($WK_CLOSE, 0, 0);
                bios($WK_PAINT, 0, 0);
                putchar('X');                      /* proof the client acted */
            }
        }
    }
    puts("BM-DONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py bm_run.c -o bm_run.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py bm_run.asm -o bm_run.bin --base 0x6A00 >/dev/null

rm -f bm.img
python3 $ROOT/tools/p8xfs.py create bm.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   bm.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  bm.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    bm.img bm_run.bin --name /bin/bm.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    bm.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# mouse press + release in the top row (cell y=1), column 26 = the CLOSE zone,
# then ^D. The press is a bar click (not a window press); the client closes WIN.
printf 'B\rrun /bin/bm.bin\r\033[<0;26;1M\033[<0;26;1m\004' > bm.in
../p8xemu -N -i bm.in -c bm.img -l 1100000000 -g bm.ppm eeprom.bin > bm.out 2>/dev/null || true
grep -q "BM-DONE" bm.out || fail "the client loop did not finish"
tr -d '\0' < bm.out | grep -q "X" || fail "the client did not receive the bar click in the CLOSE zone"

python3 - <<'EOF' || exit 1
d = open("bm.ppm", "rb").read()
px = d.split(b"\n", 3)[3]
def p(x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
GREY = (49, 48, 74)
# WIN was at (100,100); after the bar-click CLOSE it is gone -> desktop grey
assert p(100,100)==GREY, "window still present after the bar-click CLOSE: %r" % (p(100,100),)
assert p(160,150)==GREY, "window body still present after CLOSE: %r" % (p(160,150),)
print("a mouse click in the menu bar's CLOSE zone reached the client (SYS_WKEVENT")
print("event 2, column via SYS_WKARG) and closed the window -- the clickable bar works")
EOF

echo "WM-BARMENU TEST: PASS (clickable menu bar: kernel routes top-row clicks to the client with the column)"
