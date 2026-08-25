/* tri.c -- draw one 3D triangle from the shell (stage 9; a GRAPHICS-
 * LANGUAGE emitter since stage 10b, STAGE10-DESIGN.md).
 *
 *     TRI x0 y0 z0  x1 y1 z1  x2 y2 z2 [f] [k] [r g b]
 *
 * Nine world coordinates (16-bit, y UP, z INTO the screen, camera at the
 * origin), then optional flags: `f` fills the triangle, `k` KEEPS what is
 * already on screen (skips the viewport erase, so several TRI commands
 * compose into a scene), then an optional COLOUR as r g b (r,b 0-31,
 * g 0-63; white if omitted). The frame is the house default: window
 * -120..120, the centred square viewport, focal length 256 (a point at
 * z=256 maps 1:1; keep z >= 16 or the near plane clips).
 *
 * With the GL engine fitted (probe GLID) the triangle is a short command
 * stream -- WINDOW/VWPORT/FLOOD/COLOR/PRMFIL/POLY3 -- and the fabric does
 * the whole pipeline. Without one (the TTL machine) the software pipeline
 * draws the same pixels. No page flip, so POINT reads back what was drawn.
 * (The stage-9 record engine's persistent scene -- tri k stacking a list
 * that rotate/camera re-render -- returns as GL command lists, stage 10c.)
 *
 *     TRI -80 -80 300  80 -80 300  0 40 420 f      the stage-9 proof tri
 *     TRI -100 0 200  100 0 200  0 120 500         a far-leaning outline
 */
char path[2];                     /* unused; keeps the layout conventional */

//#use gfx
//#use g3d

//#define GLID   0xFF54  /* GL presence probe: 'G' when fitted            */
//#define GLDATA 0xFF50  /* the command FIFO, one byte at a time          */
//#define GLSTAT 0xFF51  /* bit7 = FIFO full (wait), bit6 = busy          */
//#define GLERR  0xFF53  /* pop one error byte; 6 = list undefined        */

char *ap;
int anum_ok;
int tp[9];
int cr; int cg; int cb;

int skipsp() {
    while (*ap == 32) { ap = ap + 1; }
    return 0;
}

int anum() {
    int v; int neg;
    skipsp();
    neg = 0; anum_ok = 0;
    if (*ap == '-') { neg = 1; ap = ap + 1; }
    v = 0;
    while (*ap >= '0' && *ap <= '9') {
        v = v * 10 + (*ap - '0');
        ap = ap + 1;
        anum_ok = 1;
    }
    if (neg) { return 0 - v; }
    return v;
}

/* one GL stream byte, honouring the FIFO's full bit */
int glb(int v) {
    while (peek(GLSTAT) & 128) { }
    poke(GLDATA, v);
    return 0;
}
int glw(int v) { glb(v & 255); glb(v >> 8); return 0; }

int main() {
    int i; int fill; int keep; int k; int go;
    ap = argstr();
    skipsp();
    if (*ap == 0 || *ap == 13 ||
        (*ap == '-' && (*(ap + 1) == 'h' || *(ap + 1) == 'H'))) {
        puts("usage: TRI x0 y0 z0 x1 y1 z1 x2 y2 z2 [f] [k] [r g b]");
        puts("  f = filled, k = keep screen (no erase); colour white if no r g b");
        return 0;
    }
    if (gpresent() == 0) { puts("?No display"); return 1; }
    i = 0;
    while (i < 9) {
        tp[i] = anum();
        if (anum_ok == 0) {
            puts("usage: TRI x0 y0 z0 x1 y1 z1 x2 y2 z2 [f] [k] [r g b]");
            return 1;
        }
        i = i + 1;
    }
    /* trailing args in ANY order: flag letters f/k, and an optional
     * colour as three numbers (the first digit starts it). No break in
     * the p8cc subset: `go` folds the exits into the loop condition. */
    fill = 0; keep = 0;
    cr = 31; cg = 63; cb = 31;
    go = 1;
    while (go) {
        skipsp();
        if (*ap == 0 || *ap == 13) { go = 0; }
        else { if (*ap == 'f' || *ap == 'F') { fill = 1; ap = ap + 1; }
        else { if (*ap == 'k' || *ap == 'K') { keep = 1; ap = ap + 1; }
        else {
            i = anum();
            if (anum_ok == 0) { go = 0; }     /* junk: stop parsing */
            else {
                cr = i;
                cg = anum();
                cb = anum();
            }
        } } }
    }
    if (peek(GLID) == 71) {
        /* the GL engine path (stage 10c): the scene IS command list 0.
         * A fresh tri RECORDS the list (erase + this triangle); tri k
         * APPENDS to it; either way CLRUN 0 redraws the whole ensemble
         * -- and rotate/camera replay the same list from new angles. */
        glb(179); glw(0 - 120); glw(120); glw(0 - 120); glw(120);
        glb(178); glw(104); glw(375); glw(0); glw(271);
        while (peek(GLERR)) { }          /* drain stale errors */
        if (keep) {
            glb(121); glb(0);            /* CLAPP 0... */
            while (peek(GLSTAT) & 64) { }
            if (peek(GLERR) == 6) {      /* ...no scene yet: start one */
                glb(112); glb(0);
            }
        } else {
            glb(112); glb(0);            /* CLBEG 0: a fresh scene */
            glb(7); glb(0); glb(0); glb(0);          /* FLOOD (recorded) */
        }
        glb(6); glb(cr); glb(cg); glb(cb);           /* COLOR  */
        glb(224); glb(fill);                         /* PRMFIL */
        glb(50); glb(3);                             /* POLY3  */
        i = 0;
        while (i < 9) { glw(tp[i]); i = i + 1; }
        glb(113);                                    /* CLEND  */
        glb(114); glb(0);                            /* CLRUN 0 */
        while (peek(GLSTAT) & 64) { }
        return 0;
    }
    /* the software pipeline (the TTL machine): same pixels */
    g3window(0 - 120, 0 - 120, 120, 120);
    g3view(104, 0, 375, 271);
    g3persp(256);
    g3clear();
    g3color(grgb(cr, cg, cb));
    g3tri(tp, fill);
    if (keep == 0) {                 /* manual erase, then walk the pool */
        gcolor(0);
        gboxf(v3x0, v3y0, v3x1, v3y1);
    }
    k = 0;
    i = 0;
    while (i < e3n) { k = e3draw(k); i = i + 1; }
    return 0;
}
