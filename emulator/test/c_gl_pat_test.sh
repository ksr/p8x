#!/bin/sh
# Stage-10j patterns. LINPAT p is DEVICE line state (every line from any
# door, MSB first, restarting each primitive; -1 = solid). AREAPT im1..16
# masks the fill spans of POLY/POLY3/RECT/SECTOR (row y&15, bit 15-(x&15));
# CLEARS/FLOOD are erases and stay solid; AREA forces the line pattern
# solid like it forces replace mode. RESETF restores both.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-PAT TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > gl_pt.c <<'EOF'
int glb(int v) { while (peek(65361) & 128) { } poke(65360, v); return 0; }
int glw(int v) { glb(v & 255); glb((v / 256) & 255); return 0; }
int apt(int even, int odd) {
    int i;
    glb(231);                                            /* AREAPT */
    i = 0;
    while (i < 16) {
        if ((i & 1) == 0) { glw(even); } else { glw(odd); }
        i = i + 1;
    }
    return 0;
}
int main() {
    glb(179); glw(0); glw(479); glw(0); glw(271);        /* WINDOW  */
    glb(178); glw(0); glw(479); glw(0); glw(271);        /* VWPORT  */
    glb(15); glb(0); glb(0); glb(0);                     /* CLEARS  */
    /* dashed white line: LINPAT $F0F0 */
    glb(6); glb(31); glb(63); glb(31);                   /* COLOR white */
    glb(234); glw(61680);                                /* LINPAT $F0F0 */
    glb(16); glw(10); glw(250);                          /* MOVE */
    glb(40); glw(200); glw(250);                         /* DRAW */
    /* solid again: LINPAT -1 */
    glb(234); glw(0 - 1);
    glb(16); glw(10); glw(240);
    glb(40); glw(200); glw(240);
    /* checkerboard AREAPT on a filled RECT */
    apt(43690, 21845);                                   /* $AAAA / $5555 */
    glb(6); glb(0); glb(63); glb(0);                     /* COLOR green */
    glb(224); glb(1);                                    /* PRMFIL 1 */
    glb(16); glw(48); glw(48);
    glb(52); glw(112); glw(112);                         /* RECT */
    glb(224); glb(0);
    /* FLOOD is an erase: stays solid under AREAPT (viewport'd corner) */
    glb(178); glw(300); glw(400); glw(30); glw(80);      /* small VWPORT */
    glb(7); glb(31); glb(0); glb(0);                     /* FLOOD red */
    glb(178); glw(0); glw(479); glw(0); glw(271);        /* VWPORT back */
    /* AREA forces the line pattern solid: outline solid, pattern set,
       fill, then a line after -- both fill and line must be solid */
    glb(6); glb(31); glb(63); glb(0);                    /* COLOR yellow */
    glb(16); glw(300); glw(150);
    glb(52); glw(360); glw(200);                         /* RECT outline */
    glb(234); glw(61680);                                /* LINPAT $F0F0 */
    glb(16); glw(330); glw(175);
    glb(192);                                            /* AREA */
    glb(16); glw(10); glw(230);                          /* post-AREA line */
    glb(40); glw(200); glw(230);
    /* RESETF restores AREAPT too */
    glb(4);                                              /* RESETF */
    glb(178); glw(0); glw(479); glw(0); glw(271);
    glb(179); glw(0); glw(479); glw(0); glw(271);
    glb(6); glb(0); glb(63); glb(31);                    /* COLOR teal */
    glb(224); glb(1);
    glb(16); glw(420); glw(200);
    glb(52); glw(460); glw(240);                         /* solid fill */
    glb(224); glb(0);
    puts("PTDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_pt.c -o gl_pt.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_pt.asm -o gl_pt.bin --base 0x6A00 >/dev/null

rm -f gl_pt.img
python3 $ROOT/tools/p8xfs.py create gl_pt.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gl_pt.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gl_pt.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_pt.img gl_pt.bin --name /bin/glpt.bin --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'B\rrun /bin/glpt.bin\r' > gl_pt.in
../p8xemu -N -i gl_pt.in -c gl_pt.img -l 900000000 -g gl_pt.ppm eeprom.bin > gl_pt.out 2>/dev/null || true
grep -q "PTDONE" gl_pt.out || fail "harness did not finish"

python3 - <<'EOF' || exit 1
d = open("gl_pt.ppm","rb").read(); px = d.split(b"\n",3)[3]
def p(x, wy):
    y = 271 - wy
    i = (y*480 + x)*3
    return tuple(px[i:i+3])
W,G,R,Y,T,B = (255,255,255),(0,255,0),(255,0,0),(255,255,0),(0,255,255),(0,0,0)
# dashed line: pixel index 0..3 on, 4..7 off ($F0F0, MSB first)
assert p(10,250)==W, "dash px0 missing: %r"%(p(10,250),)
assert p(13,250)==W, "dash px3 missing: %r"%(p(13,250),)
assert p(14,250)==B, "dash gap px4 painted: %r"%(p(14,250),)
assert p(18,250)==W, "dash px8 missing: %r"%(p(18,250),)
# LINPAT -1: solid
assert p(14,240)==W and p(100,240)==W, "solid line broken after LINPAT -1"
# checkerboard fill: the pattern is SCREEN-row indexed (apat[y&15],
# bit 15-(x&15)) -- wy 51 is screen row 220 (even -> $AAAA)
assert p(50,51)==G,  "checker even-row set bit missing: %r"%(p(50,51),)
assert p(51,51)==B,  "checker even-row clear bit painted: %r"%(p(51,51),)
assert p(50,50)==B,  "checker odd-row clear bit painted: %r"%(p(50,50),)
assert p(51,50)==G,  "checker odd-row set bit missing: %r"%(p(51,50),)
# FLOOD stays solid (VWPORT rows are SCREEN rows: y 30..80)
assert p(350,221)==R and p(351,221)==R and p(350,220)==R, "FLOOD got patterned"
# AREA forced solid: interior complete, post-AREA line solid
assert p(330,175)==Y and p(331,175)==Y, "AREA fill has pattern holes"
assert p(14,230)==Y, "line after AREA still patterned (force failed)"
# RESETF restored: teal fill solid
assert p(430,210)==T and p(431,210)==T and p(431,211)==T, "RESETF left AREAPT on"
EOF
echo "C-GL-PAT TEST: PASS (LINPAT dashes + solid restore, AREAPT checker fill, FLOOD exempt, AREA force, RESETF)"
