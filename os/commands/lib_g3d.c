/* lib_g3d.c -- wireframe 3D: a retained edge pool, a window, a viewport
 * (STAGE7-DESIGN.md). Spliced with `//#use g3d`; NEEDS `//#use gfx` ABOVE it
 * (uses gline/gboxf/gcolor). Black and white v1: g3render erases its viewport
 * to black and draws every pooled edge in white.
 *
 *     g3clear();                        empty the world
 *     g3line(x0,y0,z0, x1,y1,z1);      add one edge (world coords, int16)
 *     g3window(wx0,wy0,wx1,wy1);       view-plane rectangle to look at
 *     g3view(vx0,vy0,vx1,vy1);         screen rectangle to draw into
 *     g3persp(d);                      focal length; 0 = orthographic
 *     g3render();                      clip -> project -> map -> draw
 *
 * World: x right, y UP, z into the screen, camera fixed at the origin
 * looking down +z. The y flip happens in the viewport map alone. All three
 * of g3window/g3view/g3persp must be called before the first g3render.
 *
 * ARITHMETIC. p8cc's int is 16-bit and its < > / are UNSIGNED, so this file
 * carries its own signed machinery: s3lt (signed <) and muldiv(a,b,c) =
 * (a*b)/c through a 32-bit intermediate (shift-add multiply, then restoring
 * long division), truncating toward zero, saturating at +/-32767, 0 on c=0.
 * Every pipeline step -- the near-plane slide, the perspective divide, the
 * window clip, the viewport map -- is a muldiv shape, ~8 per drawn edge.
 * Keep world coordinates within +/-16383: the clip interpolations subtract
 * pairs of them, and a difference must also fit in an int.
 *
 * Near clip runs BEFORE the divide (an edge crossing z=Z3NEAR otherwise
 * whips across the screen as the quotient changes sign); the window clip
 * runs BEFORE anything reaches the device (the engine steps every requested
 * pixel and discards late, so a wild projected endpoint would cost tens of
 * thousands of dead steps) -- and it is what makes the viewport a true clip
 * rectangle, so viewports can sit side by side. */

//#define E3MAX  512   /* edge pool capacity (x6 ints = 6K of TPA)         */
//#define Z3NEAR 16    /* nothing nearer projects; clip slides edges here  */

int e3p[3072];                      /* the pool: E3MAX edges x x0,y0,z0,x1,y1,z1 */
int e3n;                            /* edges in the pool                   */
int w3x0; int w3y0; int w3x1; int w3y1;   /* window (view-plane coords)    */
int v3x0; int v3y0; int v3x1; int v3y1;   /* viewport (screen pixels)      */
int p3d;                            /* focal length; 0 = orthographic      */
int m3hi; int m3lo;                 /* m3mul's 32-bit product              */
int c3x0; int c3y0; int c3x1; int c3y1;   /* clip workspace                */

/* signed a < b (the < below is unsigned, which is correct once the signs
 * are known equal; differing signs: the negative one is smaller) */
int s3lt(int a, int b) {
    if ((a ^ b) & 32768) { return (a & 32768) != 0; }
    return a < b;
}

/* unsigned 16x16 -> 32 multiply into m3hi:m3lo, by shift-add: (ah:al) is
 * a shifted left once per b bit, accumulated when that bit is set. The
 * carry out of the low word is detected by unsigned wraparound (t < lo). */
int m3mul(int a, int b) {
    int hi; int lo; int ah; int al; int t;
    hi = 0; lo = 0; ah = 0; al = a;
    while (b) {
        if (b & 1) {
            t = lo + al;
            if (t < lo) { hi = hi + 1; }
            lo = t;
            hi = hi + ah;
        }
        b = b >> 1;
        ah = (ah << 1) | (al >> 15);
        al = al << 1;
    }
    m3hi = hi; m3lo = lo;
    return 0;
}

/* unsigned (m3hi:m3lo) / c -> 16-bit quotient, restoring long division,
 * saturating to 65535 when the quotient cannot fit (m3hi >= c) or c = 0.
 * The remainder's shift can carry out of 16 bits: hb catches it -- a
 * carried-out remainder is >= 65536 > c, so the subtract is forced and the
 * 16-bit wrap of (r<<1|bit)-c is exactly the true remainder. */
int u3div(int c) {
    int q; int r; int i; int hb; int bit;
    if (c == 0) { return 65535; }
    if (m3hi >= c) { return 65535; }
    r = m3hi; q = 0; i = 0;
    while (i < 16) {
        bit = 0;
        if (m3lo & 32768) { bit = 1; }
        m3lo = m3lo << 1;
        hb = r & 32768;
        r = (r << 1) | bit;
        q = q << 1;
        if (hb || (r >= c)) { r = r - c; q = q | 1; }
        i = i + 1;
    }
    return q;
}

/* (a*b)/c, signed, 32-bit intermediate, truncating toward zero,
 * saturating at +/-32767; 0/anything = 0, anything/0 saturates.
 *
 * FAST PATH: when the product fits in 16 bits (a <= 65535/b, one native
 * divide to test), the native * and / -- asm runtime routines -- do the
 * whole job ~10x cheaper than the C loops, with identical results (both
 * are truncating unsigned divides). In practice this is nearly every call:
 * the viewport map's products are <= 240*271 and a 256-focal projection's
 * are <= |x|*256, all under 65536. The C slow path only runs for genuinely
 * 32-bit products. Measured (emulator, 27 MHz): ~118k cycles slow,
 * ~10k fast. */
int muldiv(int a, int b, int c) {
    int s; int q;
    s = 0;
    if (a & 32768) { a = 0 - a; s = 1 - s; }
    if (b & 32768) { b = 0 - b; s = 1 - s; }
    if (c & 32768) { c = 0 - c; s = 1 - s; }
    if (a == 0 || b == 0) { return 0; }
    if (c != 0 && a <= 65535 / b) {
        q = (a * b) / c;
    } else {
        if (a < b) { q = a; a = b; b = q; }   /* smaller into b: fewer rounds */
        m3mul(a, b);
        q = u3div(c);
    }
    if (q > 32767) { q = 32767; }
    if (s) { return 0 - q; }
    return q;
}

/* Cohen-Sutherland outcode of (x,y) against the window */
int o3code(int x, int y) {
    int c;
    c = 0;
    if (s3lt(x, w3x0)) { c = 1; }
    if (s3lt(w3x1, x)) { c = c + 2; }
    if (s3lt(y, w3y0)) { c = c + 4; }
    if (s3lt(w3y1, y)) { c = c + 8; }
    return c;
}

/* clip the segment in c3x0..c3y1 to the window; 1 = something remains.
 * Classic Cohen-Sutherland: outcode both ends, trivial accept (both in)
 * or reject (both beyond one edge), else slide the outside end onto a
 * window edge and go round again (n bounds the pathological case). */
int c3clip() {
    int a; int b; int t; int n;
    n = 0;
    while (n < 8) {
        a = o3code(c3x0, c3y0);
        b = o3code(c3x1, c3y1);
        if ((a | b) == 0) { return 1; }
        if (a & b) { return 0; }
        if (a == 0) {                     /* make end 0 the outside one */
            t = c3x0; c3x0 = c3x1; c3x1 = t;
            t = c3y0; c3y0 = c3y1; c3y1 = t;
            a = b;
        }
        if (a & 1) {
            c3y0 = c3y0 + muldiv(c3y1 - c3y0, w3x0 - c3x0, c3x1 - c3x0);
            c3x0 = w3x0;
        } else { if (a & 2) {
            c3y0 = c3y0 + muldiv(c3y1 - c3y0, w3x1 - c3x0, c3x1 - c3x0);
            c3x0 = w3x1;
        } else { if (a & 4) {
            c3x0 = c3x0 + muldiv(c3x1 - c3x0, w3y0 - c3y0, c3y1 - c3y0);
            c3y0 = w3y0;
        } else {
            c3x0 = c3x0 + muldiv(c3x1 - c3x0, w3y1 - c3y0, c3y1 - c3y0);
            c3y0 = w3y1;
        } } }
        n = n + 1;
    }
    return 0;
}

/* window -> viewport, constant denominators; v3mapy also flips y
 * (world y is up, the screen's is down) */
int v3mapx(int sx) {
    return v3x0 + muldiv(sx - w3x0, v3x1 - v3x0, w3x1 - w3x0);
}
int v3mapy(int sy) {
    return v3y1 - muldiv(sy - w3y0, v3y1 - v3y0, w3y1 - w3y0);
}

/* the per-edge pipeline: near clip -> project -> window clip -> map -> draw */
int e3draw(int i) {
    int x0; int y0; int z0; int x1; int y1; int z1; int k;
    k = i * 6;
    x0 = e3p[k];     y0 = e3p[k + 1]; z0 = e3p[k + 2];
    x1 = e3p[k + 3]; y1 = e3p[k + 4]; z1 = e3p[k + 5];
    if (p3d) {
        if (s3lt(z0, Z3NEAR)) {
            if (s3lt(z1, Z3NEAR)) { return 0; }   /* wholly behind: drop */
            x0 = x0 + muldiv(x1 - x0, Z3NEAR - z0, z1 - z0);
            y0 = y0 + muldiv(y1 - y0, Z3NEAR - z0, z1 - z0);
            z0 = Z3NEAR;
        }
        if (s3lt(z1, Z3NEAR)) {
            x1 = x1 + muldiv(x0 - x1, Z3NEAR - z1, z0 - z1);
            y1 = y1 + muldiv(y0 - y1, Z3NEAR - z1, z0 - z1);
            z1 = Z3NEAR;
        }
        x0 = muldiv(x0, p3d, z0); y0 = muldiv(y0, p3d, z0);
        x1 = muldiv(x1, p3d, z1); y1 = muldiv(y1, p3d, z1);
    }
    c3x0 = x0; c3y0 = y0; c3x1 = x1; c3y1 = y1;
    if (c3clip() == 0) { return 0; }
    gline(v3mapx(c3x0), v3mapy(c3y0), v3mapx(c3x1), v3mapy(c3y1));
    return 0;
}

/* ---- the API ---- */

int g3clear() { e3n = 0; return 0; }

/* add one edge; 0 (and no add) once the pool is full */
int g3line(int x0, int y0, int z0, int x1, int y1, int z1) {
    int k;
    if (e3n >= E3MAX) { return 0; }
    k = e3n * 6;
    e3p[k] = x0;     e3p[k + 1] = y0; e3p[k + 2] = z0;
    e3p[k + 3] = x1; e3p[k + 4] = y1; e3p[k + 5] = z1;
    e3n = e3n + 1;
    return 1;
}

int g3window(int x0, int y0, int x1, int y1) {
    w3x0 = x0; w3y0 = y0; w3x1 = x1; w3y1 = y1;
    return 0;
}

int g3view(int x0, int y0, int x1, int y1) {
    v3x0 = x0; v3y0 = y0; v3x1 = x1; v3y1 = y1;
    return 0;
}

int g3persp(int d) { p3d = d; return 0; }

/* erase the viewport (black), then draw the whole pool in white.
 * The erase is viewport-scoped on purpose: a neighbouring viewport on the
 * same screen is left alone. (Page flipping, when it exists, replaces
 * exactly this one gboxf.) */
int g3render() {
    int i;
    gcolor(0);
    gboxf(v3x0, v3y0, v3x1, v3y1);
    gcolor(65535);
    i = 0;
    while (i < e3n) { e3draw(i); i = i + 1; }
    return 0;
}
