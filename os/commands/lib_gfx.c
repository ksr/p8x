/* lib_gfx.c -- C veneer over the display device ($FF20-$FF2F). Spliced with
 * `//#use gfx`. The device does all drawing itself (stage 6 RGB565 direct
 * colour, 480x272); these wrappers are register pokes in the right order, so
 * a filled box costs the same as an empty one and the same binary behaves
 * identically on the emulator and the FPGA (same register map, co-simmed).
 *
 * The register rules (see fpga/rtl/gfx.v):
 *   - coordinates are 16-bit PAIRS: writing a low byte ($FF20-$FF23) CLEARS
 *     its high byte; the highs sit 9 above ($FF29-$FF2C) -- one helper, gw16.
 *   - the pen is a whole RGB565 colour: GCOL low / GCOLH ($FF2D write) high,
 *     same low-write-clears-high rule.
 *   - a command ($FF25) may only be issued when GSTAT bit 7 (busy) is clear;
 *     issuing mid-draw ABORTS the running op. gwait() spins, so every g*()
 *     below is safe to call back to back.
 *   - the device treats coordinates as UNSIGNED (no sign extension): keep
 *     x in 0..479 and y in 0..271; larger values are simply not drawn
 *     (off-screen discard), but a "negative" value lands at 65535-ish, NOT
 *     off the left edge. Software that clips (lib_g3d) never sends one.
 *
 * Call gpresent() first: with no display fitted the bus floats to $FF and
 * every other call would poke the void. */

//#define GX0    0xFF20  /* x0 low  (high at +9 = $FF29)                  */
//#define GY0    0xFF21  /* y0 low  (high at $FF2A)                       */
//#define GX1    0xFF22  /* x1 low  (high at $FF2B)                       */
//#define GY1    0xFF23  /* y1 low  (high at $FF2C)                       */
//#define GCOL   0xFF24  /* pen low byte -- write CLEARS the high byte    */
//#define GCMD   0xFF25  /* command strobe (GC_* below)                   */
//#define GSTAT  0xFF26  /* bit7 = busy, bit0 = error (unknown command)   */
//#define GDATA  0xFF27  /* POINT result stream: low byte then high       */
//#define GPARM  0xFF28  /* circle radius / ellipse x-radius              */
//#define GCOLH  0xFF2D  /* pen high byte (write side of GID0)            */
//#define GID0   0xFF2D  /* reads 'P' (80) when a display is fitted       */
//#define GID1   0xFF2E  /* reads 'G' (71)                                */
//#define GPARM2 0xFF2F  /* ellipse y-radius                              */

//#define GC_PIXW 1
//#define GC_LINE 2
//#define GC_BOXF 4
//#define GC_PIXR 9
//#define GC_ELL  10
//#define GC_ELLF 11

/* wait until the engine is idle (GSTAT bit 7 clear) */
int gwait() {
    while (peek(GSTAT) & 128) { }
    return 0;
}

/* write 16-bit value v into coordinate pair r (0=x0 1=y0 2=x1 3=y1):
 * low byte first -- the low write clears the high -- then the high at +9 */
int gw16(int r, int v) {
    poke(GX0 + r, v & 255);
    poke(GX0 + 9 + r, v >> 8);
    return 0;
}

/* 1 if a display is fitted ('P','G' at GID0/GID1), else 0 */
int gpresent() {
    if (peek(GID0) != 80) { return 0; }
    if (peek(GID1) != 71) { return 0; }
    return 1;
}

/* pack an RGB565 colour: r,b 0-31, g 0-63 (masked to their fields) */
int grgb(int r, int g, int b) {
    return ((r & 31) << 11) | ((g & 63) << 5) | (b & 31);
}

/* set the 16-bit pen (a packed colour: grgb(), or a gpixelr() result) */
int gcolor(int c) {
    poke(GCOL, c & 255);          /* low first -- clears the high */
    poke(GCOLH, c >> 8);
    return 0;
}

int gcls() {
    /* the device CLS is retired (stage-10 diet): a full-screen BOXFILL
       is the same pixels through the same fill path */
    gboxf(0, 0, 479, 271);
    return 0;
}

/* the device pixel pair -- WRITE and READ (was gplot/gpoint; renamed
   so POINT names only the PGC drawing verb) */
int gpixelw(int x, int y) {
    gw16(0, x); gw16(1, y);
    gwait();
    poke(GCMD, GC_PIXW);
    return 0;
}

int gline(int x0, int y0, int x1, int y1) {
    gw16(0, x0); gw16(1, y0); gw16(2, x1); gw16(3, y1);
    gwait();
    poke(GCMD, GC_LINE);
    return 0;
}

int gbox(int x0, int y0, int x1, int y1) {
    /* the device BOX outline is retired: four LINEs, same pixels */
    gline(x0, y0, x1, y0);
    gline(x0, y1, x1, y1);
    gline(x0, y0, x0, y1);
    gline(x1, y0, x1, y1);
    return 0;
}

int gboxf(int x0, int y0, int x1, int y1) {
    gw16(0, x0); gw16(1, y0); gw16(2, x1); gw16(3, y1);
    gwait();
    poke(GCMD, GC_BOXF);
    return 0;
}

int gcircle(int x, int y, int r) {
    /* the device CIRCLE is retired: a circle IS the ellipse rx=ry */
    gellipse(x, y, r, r);
    return 0;
}

int gcirclef(int x, int y, int r) {
    gellipsef(x, y, r, r);
    return 0;
}

int gellipse(int x, int y, int rx, int ry) {
    gw16(0, x); gw16(1, y);
    poke(GPARM, rx); poke(GPARM2, ry);
    gwait();
    poke(GCMD, GC_ELL);
    return 0;
}

int gellipsef(int x, int y, int rx, int ry) {
    gw16(0, x); gw16(1, y);
    poke(GPARM, rx); poke(GPARM2, ry);
    gwait();
    poke(GCMD, GC_ELLF);
    return 0;
}

/* the colour at (x,y): issue POINT, wait, read GDATA low then high.
 * 0 for anything off-screen (the device's discard rule). */
int gpixelr(int x, int y) {
    int lo;
    gw16(0, x); gw16(1, y);
    gwait();
    poke(GCMD, GC_PIXR);
    gwait();
    lo = peek(GDATA);
    return lo | (peek(GDATA) << 8);
}
