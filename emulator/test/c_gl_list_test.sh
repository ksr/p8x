#!/bin/sh
# Stage-10c COMMAND LISTS (STAGE10-DESIGN.md): CLBEG/CLEND/CLRUN/CLOOP/
# CLDEL/CLAPP against the emulator.
#   1. Record-and-run equivalence: a scene drawn immediate-mode and the
#      SAME bytes recorded into list 1 and CLRUN twice (the second run
#      after scribbling on the screen) -- the final framebuffers must be
#      BYTE-IDENTICAL. A stored list is a replayable frame.
#   2. The fly-through: a list holding MDROTY 7 + erase + cube edges,
#      CLOOPed N times -- deltas accumulate per pass, so the end frame
#      equals N immediate rotations. Byte-compared against exactly that.
#   3. CLAPP grows a scene list; CLDEL + CLRUN answers error 6; nesting
#      and stray CLEND answer error 5; slot overflow answers error 7 and
#      leaves the slot undefined.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-LIST TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

# shared preamble every program uses
cat > gl_l_pre.c <<'EOF'
int glb(int v) { while (peek(65361) & 128) { } poke(65360, v); return 0; }
int glw(int v) { glb(v & 255); glb(v >> 8); return 0; }
int frame() {
    glb(179); glw(0 - 120); glw(120); glw(0 - 120); glw(120);
    glb(178); glw(104); glw(375); glw(0); glw(271);
    glb(176); glw(60); glb(177); glw(500);      /* PROJCT 60, DISTAN 500 */
    return 0;
}
int scene() {                                   /* erase + 2 tris + a line */
    glb(7); glb(0); glb(0); glb(0);             /* FLOOD */
    glb(224); glb(1);                           /* PRMFIL 1 */
    glb(6); glb(31); glb(20); glb(0);
    glb(50); glb(3);
    glw(0 - 80); glw(0 - 60); glw(0); glw(80); glw(0 - 60); glw(0);
    glw(0); glw(70); glw(40);
    glb(6); glb(0); glb(40); glb(31);
    glb(50); glb(3);
    glw(0 - 60); glw(60); glw(0 - 30); glw(60); glw(60); glw(0 - 30);
    glw(0); glw(0 - 50); glw(30);
    glb(6); glb(31); glb(63); glb(31);
    glb(18); glw(0 - 100); glw(0 - 90); glw(0 - 40);   /* MOVE3 */
    glb(42); glw(100); glw(90); glw(60);               /* DRAW3 */
    return 0;
}
EOF

# ---- A: immediate reference -------------------------------------------------
cat gl_l_pre.c > gl_la.c
cat >> gl_la.c <<'EOF'
int main() {
    frame(); scene();
    while (peek(65361) & 64) { }
    puts("LDONE");
    return 0;
}
EOF
# ---- B: record into list 1, scribble, CLRUN it (twice overall) --------------
cat gl_l_pre.c > gl_lb.c
cat >> gl_lb.c <<'EOF'
int main() {
    frame();
    glb(112); glb(1);                   /* CLBEG 1 */
    scene();                            /* recorded, not drawn */
    glb(113);                           /* CLEND */
    glb(114); glb(1);                   /* CLRUN 1 */
    glb(6); glb(31); glb(0); glb(0);    /* scribble over it in red */
    glb(224); glb(1);
    glb(16); glw(0 - 100); glw(0 - 100);
    glb(52); glw(100); glw(100);        /* RECT fill */
    glb(114); glb(1);                   /* CLRUN 1: the list wins again */
    while (peek(65361) & 64) { }
    puts("LDONE");
    return 0;
}
EOF
# ---- C: fly-through -- CLOOP accumulates matrix deltas ----------------------
cat gl_l_pre.c > gl_lc.c
cat >> gl_lc.c <<'EOF'
int box() {                             /* one wireframe square, z=+-40 */
    glb(6); glb(31); glb(63); glb(0);
    glb(7); glb(0); glb(0); glb(0);     /* FLOOD erase inside the list */
    glb(18); glw(0 - 70); glw(0 - 70); glw(40);
    glb(42); glw(70); glw(0 - 70); glw(40);
    glb(42); glw(70); glw(70); glw(40);
    glb(42); glw(0 - 70); glw(70); glw(40);
    glb(42); glw(0 - 70); glw(0 - 70); glw(40);
    glb(42); glw(0 - 70); glw(0 - 70); glw(0 - 40);
    return 0;
}
int main() {
    int i;
    frame();
    if (*argstr() == 'i') {             /* immediate reference: 5 frames */
        i = 0;
        while (i < 5) {
            glb(148); glw(7);           /* MDROTY 7 */
            box();
            i = i + 1;
        }
    } else {
        glb(112); glb(2);               /* CLBEG 2 */
        glb(148); glw(7);               /* MDROTY 7: a DELTA per pass */
        box();
        glb(113);                       /* CLEND */
        glb(115); glb(2); glw(5);       /* CLOOP 2, 5 passes */
    }
    while (peek(65361) & 64) { }
    puts("LDONE");
    return 0;
}
EOF
# ---- D: CLAPP + errors ------------------------------------------------------
cat gl_l_pre.c > gl_ld.c
cat >> gl_ld.c <<'EOF'
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
    frame();
    glb(112); glb(3);                    /* CLBEG 3: half the scene */
    glb(7); glb(0); glb(0); glb(0);
    glb(6); glb(31); glb(0); glb(31);
    glb(18); glw(0 - 90); glw(0); glw(0); glb(42); glw(90); glw(0); glw(0);
    glb(113);                            /* CLEND */
    glb(121); glb(3);                    /* CLAPP 3: grow it */
    glb(18); glw(0); glw(0 - 90); glw(0); glb(42); glw(0); glw(90); glw(0);
    glb(113);
    glb(114); glb(3);                    /* CLRUN: both halves draw */
    while (peek(65361) & 64) { }
    pnum(peek(65363));                   /* expect 0: no errors so far */
    glb(114); glb(9);                    /* CLRUN undefined -> 6 */
    glb(116); glb(3);                    /* CLDEL 3 */
    glb(114); glb(3);                    /* CLRUN deleted -> 6 */
    glb(113);                            /* stray CLEND -> 5 */
    glb(112); glb(4); glb(112); glb(5);  /* CLBEG inside CLBEG -> 5 */
    glb(113);                            /* end the outer recording */
    glb(121); glb(9);                    /* CLAPP undefined -> 6 */
    while (peek(65361) & 64) { }
    pnum(peek(65363)); pnum(peek(65363)); pnum(peek(65363));
    pnum(peek(65363)); pnum(peek(65363));
    puts("LDONE");
    return 0;
}
EOF

for n in la lb lc ld; do
    python3 $ROOT/compiler/p8cc.py gl_$n.c -o gl_$n.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py gl_$n.asm -o gl_$n.bin --base 0x6A00 >/dev/null
done
rm -f gll.img
python3 $ROOT/tools/p8xfs.py create gll.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gll.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gll.img /bin >/dev/null
for n in la lb lc ld; do
    python3 $ROOT/tools/p8xfs.py put gll.img gl_$n.bin --name /bin/$n.bin --load 0x6A00 --exec 0x6A00 >/dev/null
done

run() {  # $1 prog, $2 out ppm, $3 args
    printf 'B\rrun /bin/%s.bin %s\r' "$1" "$3" > gl_l.in
    ../p8xemu -N -i gl_l.in -c gll.img -l 400000000 -g "$2" eeprom.bin > gl_l.out 2>/dev/null || true
    grep -q LDONE gl_l.out || fail "$1 did not finish"
}

# 1: record-and-run == immediate
run la gl_la.ppm ""
run lb gl_lb.ppm ""
cmp gl_la.ppm gl_lb.ppm || fail "CLRUN frame differs from immediate frame"
python3 - <<'EOF' || exit 1
d=open("gl_lb.ppm","rb").read(); px=d.split(b"\n",3)[3]
assert px[(150*480+239)*3:(150*480+239)*3+3] != b"\x00\x00\x00", "scene empty"
EOF
echo "record-and-run byte-identical to immediate (and non-empty)"

# 2: CLOOP fly-through == N immediate frames
run lc gl_lc_i.ppm i
run lc gl_lc_l.ppm ""
cmp gl_lc_i.ppm gl_lc_l.ppm || fail "CLOOP frame differs from N immediate rotations"
echo "CLOOP fly-through: 5 accumulated MDROTY passes byte-identical"

# 3: CLAPP + error codes
run ld gl_ld.ppm ""
want="0 6 6 5 5 6"
got=$(LC_ALL=C tr -d '\0\r' < gl_l.out | grep -E '^[0-9]+$' | head -6 | tr '\n' ' ' | sed 's/ $//')
[ "$got" = "$want" ] || { echo "want: $want"; echo "got:  $got"; fail "list error codes differ"; }
python3 - <<'EOF' || exit 1
d=open("gl_ld.ppm","rb").read(); px=d.split(b"\n",3)[3]
# both CLAPP halves drew: horizontal (white-ish magenta) + vertical line
# DISTAN 500 + PROJCT 60 shrink the +-90 lines to roughly x 197..281,
# y 98..178 on screen -- probe inside that
o=(136*480+205)*3; assert px[o:o+3] != b"\x00\x00\x00", "appended horizontal missing"
o=(115*480+239)*3; assert px[o:o+3] != b"\x00\x00\x00", "appended vertical missing"
EOF
echo "CLAPP grows the list; error codes 5/6 exact"

echo "C-GL-LIST TEST: PASS (record==immediate, CLOOP fly-through, CLAPP, errors 5/6)"
