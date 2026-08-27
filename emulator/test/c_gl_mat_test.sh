#!/bin/sh
# Stage-10b matrix verbs (STAGE10-DESIGN.md): the card-side MD*/VW* families,
# PROJCT/DISTAN, hither/yon, CONVRT -- against a HOST REPLICA of the exact
# integer semantics (SIN8/TANH8 tables, muldiv composition, the recompose
# contract), plus the compatibility keystone: RESETF restores stage-9
# semantics exactly, proven by replaying the 10a scene and byte-comparing
# against c_gl_test's gl_b.ppm.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-MAT TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

# the reference frame for the RESETF replay
[ -f gl_b.ppm ] || sh c_gl_test.sh > /dev/null || fail "10a suite failed"

cat > gl_m.c <<'EOF'
int glb(int v) { poke(65360, v); return 0; }
int glw(int v) { glb(v & 255); glb(v >> 8); return 0; }
int main() {
    glb(179); glw(0 - 120); glw(120); glw(0 - 120); glw(120);  /* WINDOW */
    glb(178); glw(104); glw(375); glw(0); glw(271);            /* VWPORT */
    glb(7); glb(0); glb(0); glb(0);                            /* FLOOD */
    glb(6); glb(31); glb(63); glb(31);                         /* white */
    /* T1: MDTRAN pushes in; a point at the model origin */
    glb(150); glw(0); glw(0); glw(400);                        /* MDTRAN */
    glb(18); glw(60); glw(0); glw(0); glb(9);                  /* MOVE3+POINT3 */
    /* T2: rotate about the pivot: same point swings to x=0 */
    glb(6); glb(31); glb(0); glb(0);                           /* red */
    glb(144);                                                  /* MDIDEN */
    glb(150); glw(0); glw(0); glw(400);                        /* MDTRAN */
    glb(145); glw(0); glw(0); glw(400);                        /* MDORG */
    glb(148); glw(90);                                         /* MDROTY */
    glb(18); glw(60); glw(0); glw(0); glb(9);
    /* T3: the viewing orbit + DISTAN */
    glb(6); glb(0); glb(63); glb(0);                           /* green */
    glb(144);                                                  /* MDIDEN */
    glb(160);                                                  /* VWIDEN */
    glb(161); glw(0); glw(0); glw(400);                        /* VWRPT */
    glb(164); glw(90);                                         /* VWROTY */
    glb(177); glw(500);                                        /* DISTAN */
    glb(18); glw(60); glw(30); glw(400); glb(9);
    /* T4: PROJCT drives the focal */
    glb(6); glb(0); glb(0); glb(31);                           /* blue */
    glb(160); glb(161); glw(0); glw(0); glw(0);                /* VWIDEN,VWRPT 0 */
    glb(176); glw(60);                                         /* PROJCT 60 */
    glb(18); glw(0); glw(50); glw(0); glb(9);
    /* T5: yon clipping cuts a line short */
    glb(6); glb(31); glb(63); glb(0);                          /* yellow */
    glb(4);                                                    /* RESETF */
    glb(179); glw(0 - 120); glw(120); glw(0 - 120); glw(120);
    glb(178); glw(104); glw(375); glw(0); glw(271);
    glb(6); glb(31); glb(63); glb(0);
    glb(171); glb(1); glb(169); glw(600);                      /* CLIPY,DISTY */
    glb(18); glw(0 - 80); glw(0 - 60); glw(300);               /* MOVE3 */
    glb(42); glw(320); glw(0 - 60); glw(2300);                 /* DRAW3 */
    /* T6: CONVRT plants the 2D point at the 3D projection */
    glb(6); glb(0); glb(63); glb(31);                          /* cyan */
    glb(171); glb(0);                                          /* CLIPY off */
    glb(18); glw(0 - 70); glw(80); glw(500);                   /* MOVE3 */
    glb(175);                                                  /* CONVRT */
    glb(8);                                                    /* POINT (2D) */
    puts("MDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_m.c -o gl_m.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_m.asm -o gl_m.bin --base 0x6A00 >/dev/null

# the RESETF-replay program: matrix chaos, RESETF, then the EXACT 10a scene
cat > gl_r.c <<'EOF'
int glb(int v) { poke(65360, v); return 0; }
int glw(int v) { glb(v & 255); glb(v >> 8); return 0; }
int line3(int x0, int y0, int z0, int x1, int y1, int z1) {
    glb(18); glw(x0); glw(y0); glw(z0);
    glb(42); glw(x1); glw(y1); glw(z1);
    return 0;
}
int main() {
    /* scramble every 10b state, inside the viewport only */
    glb(179); glw(0 - 120); glw(120); glw(0 - 120); glw(120);
    glb(178); glw(104); glw(375); glw(0); glw(271);
    glb(147); glw(33); glb(150); glw(5); glw(6); glw(7);   /* MDROTY,MDTRAN */
    glb(164); glw(21); glb(161); glw(9); glw(9); glw(9);   /* VWROTY,VWRPT */
    glb(176); glw(90); glb(177); glw(700);                 /* PROJCT,DISTAN */
    glb(171); glb(1); glb(169); glw(90);                   /* CLIPY,DISTY */
    glb(170); glb(1); glb(168); glw(0 - 400);              /* CLIPH,DISTH */
    glb(224); glb(1);                                      /* PRMFIL 1 */
    glb(6); glb(9); glb(9); glb(9);
    glb(18); glw(1); glw(2); glw(300); glb(9);             /* a stray mark */
    glb(4);                                                /* RESETF */
    /* now the 10a scene, byte for byte as gl_b.c sent it */
    glb(179); glw(0 - 120); glw(120); glw(0 - 120); glw(120);
    glb(178); glw(104); glw(375); glw(0); glw(271);
    glb(7); glb(0); glb(0); glb(0);
    glb(6); glb(31); glb(63); glb(31);
    line3(0 - 90, 0 - 90, 300, 90, 0 - 90, 300);
    glb(6); glb(31); glb(0); glb(0);
    line3(90, 0 - 90, 300, 0, 90, 300);
    glb(6); glb(0); glb(63); glb(0);
    line3(0 - 200, 0, 300, 200, 50, 300);
    glb(6); glb(0); glb(0); glb(31);
    line3(0, 0, 0 - 50, 0, 0, 300);
    glb(224); glb(1);
    glb(6); glb(31); glb(63); glb(0);
    glb(50); glb(3);
    glw(0 - 80); glw(0 - 80); glw(300);
    glw(80);     glw(0 - 80); glw(300);
    glw(0);      glw(40);     glw(420);
    glb(6); glb(0); glb(63); glb(31);
    glb(50); glb(3);
    glw(100);    glw(0 - 140); glw(260);
    glw(140);    glw(60);      glw(260);
    glw(0 - 40); glw(10);      glw(200);
    puts("RDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_r.c -o gl_r.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_r.asm -o gl_r.bin --base 0x6A00 >/dev/null

rm -f glm.img
python3 $ROOT/tools/p8xfs.py create glm.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   glm.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  glm.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    glm.img gl_m.bin --name /bin/glm.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    glm.img gl_r.bin --name /bin/glr.bin --load 0x6A00 --exec 0x6A00 >/dev/null

# ---- 1: matrix semantics vs the host replica --------------------------------
printf 'B\rrun /bin/glm.bin\r' > gl_m.in
../p8xemu -N -i gl_m.in -c glm.img -l 300000000 -g gl_m.ppm eeprom.bin > gl_m.out 2>/dev/null || true
grep -q MDONE gl_m.out || fail "matrix program did not finish"

python3 - <<'EOF' || exit 1
import math
def muldiv(a,b,c):
    if a==0 or b==0: return 0
    q = 32767 if c==0 else min(abs(a)*abs(b)//abs(c), 32767)
    if (a<0)^(b<0)^(c<0): q=-q
    return q
def w16(v): v &= 0xFFFF; return v-65536 if v>=32768 else v
SIN8=[round(256*math.sin(math.radians(d))) for d in range(360)]
TANH8=[round(256*math.tan(math.radians(a/2.0))) for a in range(180)]
def sin(d): return SIN8[(d%360+360)%360]
def cos(d): return SIN8[(d%360+450)%360]
def mm(s,m):     # sub o m, 12-form
    r=[0]*12
    for i in range(3):
        for j in range(3):
            r[i*3+j]=w16(sum(muldiv(s[i*3+k],m[k*3+j],256) for k in range(3)))
        r[9+i]=w16(sum(muldiv(s[i*3+k],m[9+k],256) for k in range(3))+s[9+i])
    return r
def ident(): return [256,0,0, 0,256,0, 0,0,256, 0,0,0]
def rsub(ax,deg):
    c,n=cos(deg),sin(deg); s=[0]*12
    if ax==0: s[0]=256; s[4]=c; s[5]=w16(-n); s[7]=n; s[8]=c
    elif ax==1: s[0]=c; s[2]=n; s[4]=256; s[6]=w16(-n); s[8]=c
    else: s[0]=c; s[1]=w16(-n); s[3]=n; s[4]=c; s[8]=256
    return s
class GL:
    def __init__(s):
        s.m=ident(); s.v=[256,0,0,0,256,0,0,0,256]; s.rp=[0,0,0]; s.org=[0,0,0]
        s.dist=0; s.proj=60; s.pmode=0; s.h=0; s.y=0; s.ch=0; s.cy=0
        s.W=(-120,-120,120,120); s.V=(104,0,375,271); s.K=256
        s.near=16; s.far=32767
        s.recompose()
    def recompose(s):
        C=[0]*12
        for i in range(3):
            for j in range(3):
                C[i*3+j]=w16(sum(muldiv(s.v[i*3+k],s.m[k*3+j],256) for k in range(3)))
            C[9+i]=w16(sum(muldiv(s.v[i*3+k],w16(s.m[9+k]-s.rp[k]),256) for k in range(3)))
        C[11]=w16(C[11]+s.dist)
        s.C=C
        if s.pmode:
            s.K=0 if s.proj==0 else muldiv(s.W[2]-s.W[0],128,TANH8[s.proj%180])
        s.near=max(s.dist+s.h,16) if s.ch else 16
        s.far=w16(s.dist+s.y) if s.cy else 32767
    def sub(s,S): S=S[:]; \
        [S.__setitem__(9+i, w16(s.org[i]-w16(sum(muldiv(S[i*3+k],s.org[k],256) for k in range(3))))) for i in range(3)]; \
        s.m=mm(S,s.m); s.recompose()
    def xf(s,p):
        return [w16(((sum(s.C[i*3+k]*p[k] for k in range(3)))>>8)+s.C[9+i]) for i in range(3)]
    def project(s,p):
        w=s.xf(p)
        if s.K:
            if w[2]<s.near or w[2]>s.far: return None
            return (muldiv(w[0],s.K,w[2]), muldiv(w[1],s.K,w[2]))
        return (w[0],w[1])
    def mapp(s,xy):
        x,y=xy
        if not (s.W[0]<=x<=s.W[2] and s.W[1]<=y<=s.W[3]): return None
        return (s.V[0]+muldiv(x-s.W[0],s.V[2]-s.V[0],s.W[2]-s.W[0]),
                s.V[3]-muldiv(y-s.W[1],s.V[3]-s.V[1],s.W[3]-s.W[1]))
g=GL()
marks=[]   # (x, y, rgb565)
WHITE=0xFFFF; RED=31<<11; GREEN=63<<5; BLUE=31; YELLOW=(31<<11)|(63<<5); CYAN=(63<<5)|31
# T1
g.m=mm([256,0,0,0,256,0,0,0,256,0,0,400],g.m); g.recompose()
marks.append(g.mapp(g.project([60,0,0]))+(WHITE,))
# T2
g.m=ident(); g.recompose()
g.m=mm([256,0,0,0,256,0,0,0,256,0,0,400],g.m); g.recompose()
g.org=[0,0,400]
g.sub(rsub(1,90))
marks.append(g.mapp(g.project([60,0,0]))+(RED,))
# T3
g.m=ident(); g.v=[256,0,0,0,256,0,0,0,256]; g.rp=[0,0,400]; g.recompose()
g.v=[w16(x) for x in mm(rsub(1,-90),g.v+[0,0,0])[:9]]; g.recompose()
g.dist=500; g.recompose()
marks.append(g.mapp(g.project([60,30,400]))+(GREEN,))
# T4
g.v=[256,0,0,0,256,0,0,0,256]; g.rp=[0,0,0]; g.recompose()
g.proj=60; g.pmode=1; g.recompose()
marks.append(g.mapp(g.project([0,50,0]))+(BLUE,))
# T5: RESETF, then yon-clipped line: check the clipped endpoint pixel and
#     a pixel beyond it
g=GL(); g.cy=1; g.y=600; g.recompose()
a=[ -80,-60,300]; b=[320,-60,2300]
wa,wb=g.xf(a),g.xf(b)
# far clip at z=600 (replica of ge_line3t order: near first, then far)
zf=g.far
xb=w16(wa[0]+muldiv(wb[0]-wa[0],zf-wa[2],wb[2]-wa[2]))
yb=w16(wa[1]+muldiv(wb[1]-wa[1],zf-wa[2],wb[2]-wa[2]))
pa=g.mapp((muldiv(wa[0],256,wa[2]),muldiv(wa[1],256,wa[2])))
pb=g.mapp((muldiv(xb,256,zf),muldiv(yb,256,zf)))
marks.append(pa+(YELLOW,)); marks.append(pb+(YELLOW,))
beyond=g.mapp((muldiv(wb[0],256,wb[2]),muldiv(wb[1],256,wb[2])))
# T6: CONVRT point
g.cy=0; g.recompose()
w=g.xf([-70,80,500]); z=min(max(w[2],g.near),g.far)
marks.append(g.mapp((muldiv(w[0],256,z),muldiv(w[1],256,z)))+(CYAN,))

data=open("gl_m.ppm","rb").read()
hdr=data.split(b"\n",3); W,H=map(int,hdr[1].split()); px=hdr[3]
def rgb(c):
    r5,g6,b5=(c>>11)&31,(c>>5)&63,c&31
    return bytes(((r5<<3)|(r5>>2),(g6<<2)|(g6>>4),(b5<<3)|(b5>>2)))
def at(x,y):
    o=(y*W+x)*3; return px[o:o+3]
for i,(x,y,c) in enumerate(marks):
    assert at(x,y)==rgb(c), "mark %d at (%d,%d): got %r want %r" % (i,x,y,at(x,y),rgb(c))
print("replica marks:", [(x,y) for x,y,c in marks])
# the yon-clipped tail: the line must NOT reach the unclipped endpoint
bx,by=beyond
assert at(bx,by)==rgb(0), "yon clip failed: line reached (%d,%d)" % (bx,by)
print("matrix/projection/yon/CONVRT marks all verified")
EOF
echo "matrix verbs vs host replica OK"

# ---- 2: RESETF restores stage-9 semantics exactly ---------------------------
printf 'B\rrun /bin/glr.bin\r' > gl_r.in
../p8xemu -N -i gl_r.in -c glm.img -l 300000000 -g gl_r.ppm eeprom.bin > gl_r.out 2>/dev/null || true
grep -q RDONE gl_r.out || fail "RESETF program did not finish"
cmp gl_r.ppm gl_b.ppm || fail "RESETF replay differs from the 10a frame"
echo "RESETF replay byte-identical to the 10a frame"

echo "C-GL-MAT TEST: PASS (MD*/VW*/DISTAN/PROJCT/yon/CONVRT vs replica; RESETF restores stage-9 exactly)"
