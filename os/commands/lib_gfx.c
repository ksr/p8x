/* lib_gfx.c -- C veneer over the GRAPHICS LANGUAGE port ($FF50-$FF57).
 * Spliced with `//#use gfx`. SINGLE-INTERFACE since 2026-09-01: the old
 * $FF20 device-register door is gone from this library -- every call
 * emits PGC/GL bytes instead, drawn by the same engine, so the API and
 * its SCREEN-SPACE semantics (origin top-left, y DOWN) are unchanged
 * and the same binary behaves identically on the emulator and the FPGA.
 *
 * How the compatibility works:
 *   - gpresent() -- STILL the mandatory first call -- probes GLID and
 *     then ESTABLISHES the identity window/viewport (the GL port powers
 *     up with a DEGENERATE viewport) plus outline fill mode. Every
 *     wrapper then maps screen y through the identity flip (271 - y).
 *   - primitives stream through the command FIFO (GLSTAT bit7 = full,
 *     wait before pushing) and the FIFO serializes, so back-to-back
 *     calls stay safe with no per-call busy dance; gwait() drains the
 *     WALKER (GLSTAT bit6) for the places that need a finished frame.
 *   - the pen is C-side state now (__gfxpen): gcolor() records it and
 *     emits the GL COLOR verb; gcls() clears to it via FLOOD.
 *   - ONE semantic upgrade: coordinates CLIP to the screen edges (GL 2D
 *     primitives window-clip) where the old device door discarded
 *     whole off-screen pixels. Software that pre-clips (lib_g3d) sees
 *     no difference.
 */

//#define GLDATA 0xFF50  /* write: push one GL command byte             */
//#define GLSTAT 0xFF51  /* bit7 FIFO full, bit6 busy, bit0 read-back   */
//#define GLRB   0xFF52  /* pop one read-back byte (PIXRD's reply)      */
//#define GLID   0xFF54  /* reads 'G' (71) when the engine is fitted    */

int __gfxpen;
int __gfxini;

/* push one GL byte, honouring FIFO backpressure -- and SELF-ESTABLISH
 * the library's ground state on first use (identity window/viewport:
 * the port powers up DEGENERATE; outline fill; white pen state). The
 * flag is set BEFORE the init bytes go out, so their own glbyt calls
 * pass straight through. This keeps every entry point safe even for
 * clients that never call gpresent() (lib_g3d's software path). */
int glbyt(int v) {
    if (__gfxini == 0) {
        __gfxini = 1;
        __gfxpen = 65535;
        glbyt(179); glwrd(0); glwrd(479); glwrd(0); glwrd(271);
        glbyt(178); glwrd(0); glwrd(479); glwrd(0); glwrd(271);
        glbyt(224); glbyt(0);
    }
    while (peek(GLSTAT) & 128) { }
    poke(GLDATA, v);
    return 0;
}

/* one int16 parameter, little-endian */
int glwrd(int v) {
    glbyt(v & 255);
    glbyt((v / 256) & 255);
    return 0;
}

/* wait until the walker is idle (GLSTAT bit 6 clear) */
int gwait() {
    while (peek(GLSTAT) & 64) { }
    return 0;
}

/* 1 if the GL engine is fitted ('G' at GLID), else 0 -- and on success
 * establish the library's ground state: identity window + viewport
 * (the port powers up degenerate), outline fill, a known white pen */
int gpresent() {
    if (peek(GLID) != 71) { return 0; }
    gcolor(65535);           /* triggers the lazy init + a known pen */
    return 1;
}

/* MOVE to screen (x,y) -- the shared verb+flip every primitive opens
 * with, and the library's size discipline: g3d clients live a few
 * hundred bytes below CSTACKTOP, so shared inners beat inline emission */
int glmov(int x, int y) {
    glbyt(16); glwrd(x); glwrd(271 - y);
    return 0;
}

/* opcode + the pen unpacked to r g b (COLOR and FLOOD share the shape) */
int glrgb(int op, int c) {
    glbyt(op);
    glbyt((c >> 11) & 31);
    glbyt((c >> 5) & 63);
    glbyt(c & 31);
    return 0;
}

int glpf(int f) {
    glbyt(224); glbyt(f);
    return 0;
}

/* pack an RGB565 colour: r,b 0-31, g 0-63 (masked to their fields) */
int grgb(int r, int g, int b) {
    return ((r & 31) << 11) | ((g & 63) << 5) | (b & 31);
}

/* set the 16-bit pen (a packed colour: grgb(), or a gpixelr() result) */
int gcolor(int c) {
    __gfxpen = c;
    glrgb(6, c);                         /* COLOR */
    return 0;
}

/* clear the whole screen TO THE PEN colour (FLOOD carries its own) */
int gcls() {
    glrgb(7, __gfxpen);                  /* FLOOD */
    return 0;
}

/* the pixel pair -- WRITE and READ, screen coords, exact old semantics */
int gpixelw(int x, int y) {
    glmov(x, y);
    glbyt(8);                            /* POINT */
    return 0;
}

int gline(int x0, int y0, int x1, int y1) {
    glmov(x0, y0);
    glbyt(40); glwrd(x1); glwrd(271 - y1);   /* DRAW */
    return 0;
}

/* RECT's outline is pixel-identical to the old four-line box */
int gbox(int x0, int y0, int x1, int y1) {
    glmov(x0, y0);
    glbyt(52); glwrd(x1); glwrd(271 - y1);   /* RECT */
    return 0;
}

int gboxf(int x0, int y0, int x1, int y1) {
    glpf(1); gbox(x0, y0, x1, y1); glpf(0);
    return 0;
}

int gcircle(int x, int y, int r) {
    gellipse(x, y, r, r);
    return 0;
}

int gcirclef(int x, int y, int r) {
    glpf(1); gellipse(x, y, r, r); glpf(0);
    return 0;
}

int gellipse(int x, int y, int rx, int ry) {
    glmov(x, y);
    glbyt(57); glwrd(rx); glwrd(ry);         /* ELIPSE */
    return 0;
}

/* with PRMFIL up, the same ELIPSE fills */
int gellipsef(int x, int y, int rx, int ry) {
    glpf(1); gellipse(x, y, rx, ry); glpf(0);
    return 0;
}

/* the colour at (x,y): the PIXRD verb, reply through the RB FIFO
 * (low byte then high). 0 for anything off-screen, the old rule. */
int gpixelr(int x, int y) {
    int lo;
    glbyt(99); glwrd(x); glwrd(271 - y);     /* PIXRD (no glmov: it is
                                                a read, not a MOVE) */
    while ((peek(GLSTAT) & 1) == 0) { }
    lo = peek(GLRB);
    while ((peek(GLSTAT) & 1) == 0) { }
    return lo | (peek(GLRB) << 8);
}
