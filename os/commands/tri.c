/* tri.c -- draw one 3D triangle from the shell (the g3tri primitive as a
 * command; stage 9, STAGE9-DESIGN.md).
 *
 *     TRI x0 y0 z0  x1 y1 z1  x2 y2 z2 [f] [k] [r g b]
 *
 * Nine world coordinates (16-bit, y UP, z INTO the screen, camera at the
 * origin), then optional flags: `f` fills the triangle, `k` KEEPS what is
 * already on screen (skips the viewport erase, so several TRI commands
 * compose into a scene), then an optional COLOUR as r g b (r,b 0-31,
 * g 0-63; white if omitted). The frame
 * is the house default: window -120..120, the centred square viewport,
 * focal length 256 (a point at z=256 maps 1:1; keep z >= 16 or the near
 * plane clips). Renders through the geometry engine when fitted, else the
 * software pipeline -- same pixels either way. No page flip, so POINT
 * reads back exactly what was drawn.
 *
 *     TRI -80 -80 300  80 -80 300  0 40 420 f      the stage-9 proof tri
 *     TRI -100 0 200  100 0 200  0 120 500         a far-leaning outline
 */
char path[2];                     /* unused; keeps the layout conventional */

//#use gfx
//#use g3d

char *ap;
int anum_ok;
int tp[9];

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
                k = anum();
                g3color(grgb(i, k, anum()));
            }
        } } }
    }
    g3window(0 - 120, 0 - 120, 120, 120);
    g3view(104, 0, 375, 271);
    g3persp(256);
    g3clear();
    g3tri(tp, fill);
    if (g3probe()) {
        /* the engine list is a persistent SCENE (stage 9c): `k` APPENDS
         * this record after the persisted ones (the upload cursor survives
         * between commands; count reads back), so triangles stack -- and
         * rotate redraws the whole ensemble. Without k: a fresh scene. */
        if (keep) {
            i = g3parrd(22);         /* current record count */
            k = 0;
            while (k < e3o) {        /* upload WITHOUT rewinding */
                poke(GEUP, e3p[k]);
                poke(GEUP, e3p[k] >> 8);
                k = k + 1;
            }
            g3par(22, i + e3n);
            g3flags(0);              /* draw over the scene, no erase */
        } else {
            g3up();                  /* rewinds and replaces the scene */
            g3flags(1);
        }
        g3go();
        return 0;
    }
    if (keep == 0) {                 /* software: manual erase, then walk */
        gcolor(0);
        gboxf(v3x0, v3y0, v3x1, v3y1);
    }
    k = 0;
    i = 0;
    while (i < e3n) { k = e3draw(k); i = i + 1; }
    return 0;
}
