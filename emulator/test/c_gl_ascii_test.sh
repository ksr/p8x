#!/bin/sh
# Stage-10d ASCII mode (STAGE10-DESIGN.md): the translator front-end.
#   1. THE crown-jewel: c_gl_test's hex scene written as ASCII TEXT
#      (long forms, mixed delimiters and case) must produce a frame
#      BYTE-IDENTICAL to the hex stream's gl_b.ppm.
#   2. Short forms: the same scene again in the manual's abbreviations --
#      identical frame again.
#   3. Recording in ASCII: a CLBEG/CLEND list typed as text, replayed by
#      hex CLRUN after CX -- lists store HEX, so replay is mode-blind.
#   4. Error recovery is deterministic: unknown keyword logs 1 and eats
#      its numbers; a keyword arriving early logs 2 and ZERO-FILLS; an
#      orphaned number logs 2; the stream stays in sync throughout.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-ASCII TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
[ -f gl_b.ppm ] || sh c_gl_test.sh > /dev/null || fail "10a suite failed"

# a tiny sender: switches to ASCII, streams a string, back to hex
cat > gl_as_pre.c <<'EOF'
int glb(int v) { while (peek(65361) & 128) { } poke(65360, v); return 0; }
int gls(char *s) {
    while (*s) { glb(*s); s = s + 1; }
    return 0;
}
int main() {
    glb(67); glb(65); glb(32);          /* hex "CA ": enter ASCII */
EOF

# ---- 1: the 10a scene as ASCII text ----------------------------------------
cat gl_as_pre.c > gl_as1.c
cat >> gl_as1.c <<'EOF'
    gls("window -120 120 -120 120\r");
    gls("VWPORT 104,375,0,271\r");
    gls("Flood 0 0 0\r");
    gls("COLOR 31 63 31; MOVE3 -90 -90 300; DRAW3 90,-90,300\r");
    gls("COLOR 31 0 0\rMOVE3 90 -90 300\rDRAW3 0 90 300\r");
    gls("color 0 63 0 move3 -200 0 300 draw3 200 50 300\r");
    gls("COLOR 0 0 31 MOVE3 0 0 -50 DRAW3 0 0 300\r");
    gls("PRMFIL 1\r");
    gls("COLOR 31 63 0\r");
    gls("POLY3 3 -80 -80 300 80 -80 300 0 40 420\r");
    gls("COLOR 0 63 31\r");
    gls("POLY3 3 100 -140 260 140 60 260 -40 10 200\r");
    gls("CX ");
    while (peek(65361) & 64) { }
    puts("A1DONE");
    return 0;
}
EOF
# ---- 2: short forms --------------------------------------------------------
cat gl_as_pre.c > gl_as2.c
cat >> gl_as2.c <<'EOF'
    gls("WI -120 120 -120 120\rVWP 104 375 0 271\rF 0 0 0\r");
    gls("C 31 63 31 M3 -90 -90 300 D3 90 -90 300\r");
    gls("C 31 0 0 M3 90 -90 300 D3 0 90 300\r");
    gls("C 0 63 0 M3 -200 0 300 D3 200 50 300\r");
    gls("C 0 0 31 M3 0 0 -50 D3 0 0 300\r");
    gls("PF 1 C 31 63 0\r");
    gls("P3 3 -80 -80 300 80 -80 300 0 40 420\r");
    gls("C 0 63 31\r");
    gls("P3 3 100 -140 260 140 60 260 -40 10 200\r");
    gls("CX ");
    while (peek(65361) & 64) { }
    puts("A2DONE");
    return 0;
}
EOF
# ---- 3: record a list in ASCII, replay it by hex ---------------------------
cat gl_as_pre.c > gl_as3.c
cat >> gl_as3.c <<'EOF'
    gls("WINDOW -120 120 -120 120\rVWPORT 104 375 0 271\r");
    gls("CLBEG 7\r");
    gls("FLOOD 0 0 0\rCOLOR 31 63 0\rPRMFIL 1\r");
    gls("POLY3 3 -80 -80 300 80 -80 300 0 40 420\r");
    gls("CLEND\r");
    gls("CX ");
    glb(114); glb(7);                   /* hex CLRUN 7 */
    while (peek(65361) & 64) { }
    puts("A3DONE");
    return 0;
}
EOF
# ---- 4: error recovery -----------------------------------------------------
cat > gl_as4.c <<'EOF'
int glb(int v) { while (peek(65361) & 128) { } poke(65360, v); return 0; }
int gls(char *s) {
    while (*s) { glb(*s); s = s + 1; }
    return 0;
}
char pb[8];
int pnum(int u) {
    int i;
    i = 0;
    if (u == 0) { putchar(48); }
    while (u) { pb[i] = 48 + (u % 10); u = u / 10; i = i + 1; }
    while (i) { i = i - 1; putchar(pb[i]); }
    putchar(10);
    return 0;
}
int main() {
    glb(67); glb(65); glb(32);
    gls("WINDOW 0 239 0 135\rVWPORT 0 239 0 135\rCOLOR 31 63 31\r");
    gls("BOGUS 1 2 3\r");                /* unknown kw: err 1, numbers eaten */
    gls("MOVE 10 MOVE 10 10\r");         /* early kw: err 2, zero-filled     */
    gls("77\r");                         /* orphaned number: err 2           */
    gls("DRAW 50 10\r");                 /* still in sync: draws (0,10)->(50,10)? no:
                                            the zero-filled MOVE was (10,0) then
                                            MOVE 10 10 -- current point 10,10  */
    gls("CX ");
    while (peek(65361) & 64) { }
    pnum(peek(65363)); pnum(peek(65363)); pnum(peek(65363));
    pnum(peek(65363));
    puts("A4DONE");
    return 0;
}
EOF

for n in 1 2 3 4; do
    python3 $ROOT/compiler/p8cc.py gl_as$n.c -o gl_as$n.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py gl_as$n.asm -o gl_as$n.bin --base 0x6A00 >/dev/null
done
rm -f gla.img
python3 $ROOT/tools/p8xfs.py create gla.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gla.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gla.img /bin >/dev/null
for n in 1 2 3 4; do
    python3 $ROOT/tools/p8xfs.py put gla.img gl_as$n.bin --name /bin/as$n.bin --load 0x6A00 --exec 0x6A00 >/dev/null
done

run() {
    printf 'B\rrun /bin/as%s.bin\r' "$1" > gl_as.in
    ../p8xemu -N -i gl_as.in -c gla.img -l 400000000 -g "$2" eeprom.bin > gl_as.out 2>/dev/null || true
    grep -q "A${1}DONE" gl_as.out || fail "program $1 did not finish"
}

run 1 gl_as1.ppm
cmp gl_as1.ppm gl_b.ppm || fail "ASCII long-form frame differs from the hex frame"
echo "ASCII long forms byte-identical to hex"

run 2 gl_as2.ppm
cmp gl_as2.ppm gl_b.ppm || fail "ASCII short-form frame differs"
echo "short forms byte-identical too"

run 3 gl_as3.ppm
python3 - <<'EOF' || exit 1
d=open("gl_as3.ppm","rb").read(); px=d.split(b"\n",3)[3]
o=(170*480+239)*3
assert px[o:o+3] == b"\xff\xff\x00", "ASCII-recorded list did not replay"
EOF
echo "ASCII-recorded list replays from hex CLRUN"

run 4 gl_as4.ppm
want="1 2 2 0"
got=$(LC_ALL=C tr -d '\0\r' < gl_as.out | grep -E '^[0-9]+$' | head -4 | tr '\n' ' ' | sed 's/ $//')
[ "$got" = "$want" ] || { echo "want: $want"; echo "got:  $got"; fail "ASCII error codes differ"; }
python3 - <<'EOF' || exit 1
d=open("gl_as4.ppm","rb").read(); px=d.split(b"\n",3)[3]
# after recovery: MOVE 10 10 then DRAW 50 10 -> line at screen y=125
o=(125*480+30)*3
assert px[o:o+3] == b"\xff\xff\xff", "post-recovery line missing: stream desynced"
EOF
echo "error recovery deterministic, stream stays in sync"

echo "C-GL-ASCII TEST: PASS (long forms, short forms, ASCII-recorded lists, error recovery)"
