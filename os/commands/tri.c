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
    int i; int fill; int keep; int k;
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
    fill = 0; keep = 0;
    skipsp();
    while (*ap == 'f' || *ap == 'F' || *ap == 'k' || *ap == 'K' || *ap == 32) {
        if (*ap == 'f' || *ap == 'F') { fill = 1; }
        if (*ap == 'k' || *ap == 'K') { keep = 1; }
        ap = ap + 1;
    }
    i = anum();                       /* optional colour: r g b */
    if (anum_ok) {
        k = anum();
        g3color(grgb(i, k, anum()));
    }
    g3window(0 - 120, 0 - 120, 120, 120);
    g3view(104, 0, 375, 271);
    g3persp(256);
    g3clear();
    g3tri(tp, fill);
    if (g3probe()) {
        i = 1;                       /* engine: erase unless k, never flip */
        if (keep) { i = 0; }
        g3flags(i);
        g3up();
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
