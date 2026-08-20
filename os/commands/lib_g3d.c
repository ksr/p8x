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

//#define E3MAX  512   /* pool capacity in RECORDS (LINE = 8 ints; 8K)     */
//#define Z3NEAR 16    /* nothing nearer projects; clip slides edges here  */

/* The MDU (stage 8a, STAGE8-DESIGN.md): a hardware muldiv at $FF30 that
 * implements THIS library's contract bit for bit. muldiv() probes for it
 * once (MDID reads 'M'; an absent unit floats to $FF) and routes through
 * it when present -- the same source runs on an old bitstream, the
 * emulator, and the new silicon, fastest path chosen at runtime. */
//#define MDA    0xFF30  /* operand a low (write clears high; high at +9) */
//#define MDB    0xFF31
//#define MDC    0xFF32
//#define MDQ    0xFF33  /* read: result low                              */
//#define MDGO   0xFF34  /* write anything: start                         */
//#define MDSTAT 0xFF35  /* read: bit7 busy                               */
//#define MDID   0xFF36  /* read: 'M' ($4D) when the MDU is fitted        */
//#define MDAH   0xFF39
//#define MDBH   0xFF3A
//#define MDCH   0xFF3B
//#define MDQH   0xFF3C

/* The geometry engine (stage 8b, STAGE8B-DESIGN.md): the whole pipeline in
 * fabric. The edge list lives in SDRAM (uploaded through GEUP), a 12-word
 * S7.8 matrix+translation lives in an INDEXED parameter file (GESEL picks,
 * GEVAL low latches, GEVALH commits and auto-increments), and one command
 * renders the list. g3render() auto-routes through it with an identity
 * matrix -- bit-identical pixels, ~30x fewer CPU cycles -- and the pro path
 * (g3up/g3mat/g3go) uploads a STATIC model once and re-renders it per frame
 * with only a matrix write. GEID reads 'E'; absent engines fall back to the
 * stage-7 software walk, same source, forever. */
//#define GESEL  0xFF40  /* parameter index: 0-8 matrix, 9-11 t, 12 focal,  */
//#define GEVAL  0xFF41  /*   13-16 window, 17-20 viewport, 21 flags,      */
//#define GEUP   0xFF42  /*   22 edge count                                 */
//#define GECMD  0xFF43  /* 1 rewind upload cursor / 2 RENDER / 3 FLIP      */
//#define GESTAT 0xFF44  /* bit7 busy, bit0 err                             */
//#define GEID   0xFF45  /* reads 'E' ($45) when an engine is fitted        */
//#define GEVALH 0xFF4A  /* value high: commits reg[GESEL], GESEL++         */

int e3p[4096];                      /* the pool: E3MAX 16-byte LINE records */
int e3n;                            /* RECORDS in the pool                 */
int e3o;                            /* pool write offset (ints)            */
int p3col;                          /* pool pen for new records            */
int p3ci;                           /* pool pen initialized? (default white) */
int w3x0; int w3y0; int w3x1; int w3y1;   /* window (view-plane coords)    */
int v3x0; int v3y0; int v3x1; int v3y1;   /* viewport (screen pixels)      */
int p3d;                            /* focal length; 0 = orthographic      */
int m3hi; int m3lo;                 /* m3mul's 32-bit product              */
int m3has;                          /* MDU probe: 0 unknown, 1 yes, 2 no   */
int g3has;                          /* engine probe: same three states     */
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
    if (m3has == 0) {                     /* probe once, remember */
        if (peek(MDID) == 77) { m3has = 1; } else { m3has = 2; }
    }
    if (m3has == 1) {                     /* the MDU implements the contract */
        poke(MDA, a); poke(MDAH, a >> 8); /* poke stores the LOW byte, so   */
        poke(MDB, b); poke(MDBH, b >> 8); /*   no & 255 mask is needed      */
        poke(MDC, c); poke(MDCH, c >> 8);
        poke(MDGO, 1);
        while (peek(MDSTAT) & 128) { }
        return peek(MDQ) | (peek(MDQH) << 8);
    }
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

/* the per-record pipeline: pen, near clip -> project -> clip -> map -> draw.
 * k is the record's POOL OFFSET (ints); returns the next record's offset. */
int e3draw(int k) {
    int x0; int y0; int z0; int x1; int y1; int z1;
    gcolor(e3p[k + 1]);             /* the record's own colour */
    x0 = e3p[k + 2]; y0 = e3p[k + 3]; z0 = e3p[k + 4];
    x1 = e3p[k + 5]; y1 = e3p[k + 6]; z1 = e3p[k + 7];
    k = k + 8;
    if (p3d) {
        if (s3lt(z0, Z3NEAR)) {
            if (s3lt(z1, Z3NEAR)) { return k; }   /* wholly behind: drop */
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
    if (c3clip() == 0) { return k; }
    gline(v3mapx(c3x0), v3mapy(c3y0), v3mapx(c3x1), v3mapy(c3y1));
    return k;
}

/* ---- the geometry engine path (stage 8b) ---- */

/* 1 if the engine is fitted (GEID reads 'E'; an absent one floats to $FF) */
int g3probe() {
    if (g3has == 0) {
        if (peek(GEID) == 69) { g3has = 1; } else { g3has = 2; }
    }
    if (g3has == 1) { return 1; }
    return 0;
}

/* write one engine parameter: reg[s] = v (GEVALH commits) */
int g3par(int s, int v) {
    poke(GESEL, s);
    poke(GEVAL, v);
    poke(GEVALH, v >> 8);
    return 0;
}

/* upload the pool as the engine's edge list; 1 if an engine took it */
int g3up() {
    int i; int n; int k;
    if (g3probe() == 0) { return 0; }
    poke(GECMD, 1);                    /* rewind the upload cursor */
    n = e3o;                           /* ints in the record stream */
    i = 0;
    while (i < n) {                    /* stream int16s little-endian */
        k = e3p[i];
        poke(GEUP, k);
        poke(GEUP, k >> 8);
        i = i + 1;
    }
    g3par(22, e3n);                    /* edge count */
    return 1;
}

/* load the transform: m[12] = 8.8 matrix row-major, then tx,ty,tz.
 * GEVALH's auto-increment makes this one GESEL poke + 24 GEVAL pokes. */
int g3mat(int *m) {
    int i;
    if (g3probe() == 0) { return 0; }
    poke(GESEL, 0);
    i = 0;
    while (i < 12) {
        poke(GEVAL, m[i]);
        poke(GEVALH, m[i] >> 8);
        i = i + 1;
    }
    return 1;
}

/* render flags: bit0 = erase viewport first, bit1 = page-flip after
 * (power-on default 3). Flip shows each finished frame at the scanout
 * frame boundary -- but POINT reads the DRAW page, so a program that
 * wants to read back what it just rendered should use flags 1. */
int g3flags(int f) {
    if (g3probe() == 0) { return 0; }
    g3par(21, f);
    return 1;
}

/* flip the pages by hand (display <- draw, draw <- the other page); waits
 * out the vsync-latched flip. For CPU-drawn double buffering. */
int g3flip() {
    if (g3probe() == 0) { return 0; }
    poke(GECMD, 3);
    while (peek(GESTAT) & 128) { }
    return 1;
}

/* back to single-buffer: the draw page REJOINS the display page (instant).
 * After any flipping, call this before handing the screen to code that
 * expects PLOT/POINT to touch what it sees -- flips leave the two pages
 * opposite by construction, and there is no other way back. */
int g3sync() {
    if (g3probe() == 0) { return 0; }
    poke(GECMD, 4);
    return 1;
}

/* render the UPLOADED list with the current matrix and the library's
 * window/viewport/focal; 1 when an engine did it, 0 when absent
 * (caller falls back to the software walk -- see g3render). */
int g3go() {
    if (g3probe() == 0) { return 0; }
    g3par(12, p3d);
    g3par(13, w3x0); g3par(14, w3y0); g3par(15, w3x1); g3par(16, w3y1);
    g3par(17, v3x0); g3par(18, v3y0); g3par(19, v3x1); g3par(20, v3y1);
    poke(GECMD, 2);
    while (peek(GESTAT) & 128) { }
    return 1;
}

/* ---- the API ---- */

int g3clear() { e3n = 0; e3o = 0; return 0; }

/* the pool pen: every record added after this carries colour c
 * (stage 9 -- records are typed and each owns its RGB565 colour).
 * Before the first g3color the pen is white. */
int g3color(int c) {
    p3col = c;
    p3ci = 1;
    return 0;
}

/* add one LINE record; 0 (and no add) once the pool is full */
int g3line(int x0, int y0, int z0, int x1, int y1, int z1) {
    int k;
    if (p3ci == 0) { p3col = 65535; p3ci = 1; }
    if (e3n >= E3MAX) { return 0; }
    k = e3o;
    e3p[k] = 1;                     /* type 1 = LINE, flags 0     */
    e3p[k + 1] = p3col;
    e3p[k + 2] = x0; e3p[k + 3] = y0; e3p[k + 4] = z0;
    e3p[k + 5] = x1; e3p[k + 6] = y1; e3p[k + 7] = z1;
    e3o = e3o + 8;
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
 * With a geometry engine fitted this auto-routes: upload the pool, load
 * the IDENTITY matrix (exact: (v*256)>>8 == v), erase-no-flip flags --
 * bit-identical pixels to the software walk below, stage-7 semantics
 * preserved (single page, POINT sees what was drawn), ~30x less CPU.
 * The engine owns the matrix here; the pro path (g3mat/g3go) sets its
 * own every frame anyway. Without an engine: the software walk, with
 * the erase viewport-scoped on purpose -- a neighbouring viewport on
 * the same screen is left alone. */
int g3render() {
    int i; int k;
    if (g3probe()) {
        g3up();
        poke(GESEL, 0);
        i = 0;
        while (i < 12) {
            k = 0;
            if (i == 0 || i == 4 || i == 8) { k = 256; }
            poke(GEVAL, k);
            poke(GEVALH, k >> 8);
            i = i + 1;
        }
        g3par(21, 1);                  /* erase, no flip */
        g3go();
        return 0;
    }
    gcolor(0);
    gboxf(v3x0, v3y0, v3x1, v3y1);
    k = 0;
    i = 0;
    while (i < e3n) { k = e3draw(k); i = i + 1; }
    return 0;
}
