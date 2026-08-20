/* image.c -- view and GRAB P8I pictures from the shell, no BASIC needed.
 *
 *     IMAGE x y file               draw a P8I picture with its top-left at x,y
 *     IMAGE READ x0 y0 x1 y1 file  grab that screen rectangle INTO a P8I file
 *
 * The two verbs are inverses, and P8I's self-describing header (magic,
 * version, width, height, depth -- see tools/p8img.py / STAGE6-DESIGN.md) is
 * what makes that composition work: anything grabbed is immediately
 * re-drawable by either this command or BASIC's IMAGE, and `p8xfs get` +
 * p8img can lift a grab to the host as a real screenshot.
 *
 * Draw: FGETB the header, validate ("?NOT P8I" on bad magic/version/depth or
 * a truncated payload, "?No file" if missing), then per pixel: two bytes ->
 * gcolor -> gplot. Off-screen pixels are discarded by the device, so an
 * image may hang off any edge. Grab: corners self-sort like BOX; each pixel
 * is gpoint()ed and written little-endian after a 10-byte header. An
 * existing file of the same name is REPLACED (FDELETE then rewrite). Grabs
 * read the DRAW page, so if a geometry engine is fitted the command issues
 * PGSYNC first -- a grab always captures what the panel shows. A grab costs
 * a few hundred cycles per pixel: a full-screen 480x272 rectangle is ~130k
 * reads and takes tens of seconds. That is what it costs; it is a utility.
 *
 * The pen is left on the last pixel colour drawn/probed -- like IMAGE in
 * BASIC, set COLOR/gcolor afterwards before drawing your own things. */
char path[80];

//#use apath   /* abspath(out, arg): path word -> absolute, CWD-relative */
//#use abi     /* FRESOLVE/FOPEN/FGETB/FWOPEN/FPUTB/FCLOSE/FDELETE, RDBUF */
//#use gfx     /* gpresent/gcolor/gplot/gpoint */

//#define GEID   0xFF45  /* geometry-engine probe ('E' when fitted)        */
//#define GECMD  0xFF43  /* its command port: 4 = PGSYNC (draw = display)  */

char *ap;                          /* argument cursor */
int anum_ok;                       /* did anum() actually see digits?      */

int skipsp() {
    while (*ap == 32) { ap = ap + 1; }
    return 0;
}

/* parse a signed decimal number at ap (p8cc's < > are unsigned, so the
 * sign is handled by explicit negation, never by comparing) */
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

int usage() {
    puts("usage: IMAGE x y file                draw a P8I picture at x,y");
    puts("       IMAGE READ x0 y0 x1 y1 file   grab the rectangle to a P8I");
    return 0;
}

/* draw the P8I at `path` with its top-left at (x,y) */
int draw(int x, int y) {
    int w; int h; int px; int py; int lo; int hi;
    bios(FRESOLVE, path, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { puts("?No file"); return 1; }
    if ((bios(FGETB, 0, 0) & 511) != 'P') { puts("?NOT P8I"); return 1; }
    if ((bios(FGETB, 0, 0) & 511) != '8') { puts("?NOT P8I"); return 1; }
    if ((bios(FGETB, 0, 0) & 511) != 'I') { puts("?NOT P8I"); return 1; }
    if ((bios(FGETB, 0, 0) & 511) != 1)   { puts("?NOT P8I"); return 1; }
    lo = bios(FGETB, 0, 0); hi = bios(FGETB, 0, 0);
    if ((lo | hi) & 256) { puts("?NOT P8I"); return 1; }
    w = (lo & 255) | ((hi & 255) << 8);
    lo = bios(FGETB, 0, 0); hi = bios(FGETB, 0, 0);
    if ((lo | hi) & 256) { puts("?NOT P8I"); return 1; }
    h = (lo & 255) | ((hi & 255) << 8);
    if ((bios(FGETB, 0, 0) & 511) != 16) { puts("?NOT P8I"); return 1; }
    bios(FGETB, 0, 0);                       /* reserved byte */
    if (w == 0 || h == 0) { puts("?NOT P8I"); return 1; }
    py = 0;
    while (py < h) {
        px = 0;
        while (px < w) {
            lo = bios(FGETB, 0, 0);
            hi = bios(FGETB, 0, 0);
            if ((lo | hi) & 256) { puts("?NOT P8I"); return 1; }  /* short */
            gcolor((lo & 255) | ((hi & 255) << 8));
            gplot(x + px, y + py);           /* off-screen: discarded */
            px = px + 1;
        }
        py = py + 1;
    }
    return 0;
}

/* grab the (sorted) rectangle into a fresh P8I at `path` */
int grab(int x0, int y0, int x1, int y1) {
    int t; int w; int h; int px; int py; int c;
    if (x1 < x0) { t = x0; x0 = x1; x1 = t; }     /* self-sort, like BOX  */
    if (y1 < y0) { t = y0; y0 = y1; y1 = t; }     /* (coords 0..479/271)  */
    w = x1 - x0 + 1;
    h = y1 - y0 + 1;
    if (peek(GEID) == 69) { poke(GECMD, 4); }     /* PGSYNC: grab what shows */
    bios(FRESOLVE, path, 0);
    bios(FDELETE, 0, 0);                    /* replace an existing file   */
    bios(FRESOLVE, path, 0);                /* FDELETE walked the dir     */
    bios(FWOPEN, 0, 0);
    bios(FPUTB, 0, 'P'); bios(FPUTB, 0, '8'); bios(FPUTB, 0, 'I');
    bios(FPUTB, 0, 1);
    bios(FPUTB, 0, w); bios(FPUTB, 0, w >> 8);
    bios(FPUTB, 0, h); bios(FPUTB, 0, h >> 8);
    bios(FPUTB, 0, 16); bios(FPUTB, 0, 0);
    py = y0;
    while (py <= y1) {
        px = x0;
        while (px <= x1) {
            c = gpoint(px, py);             /* 0 for anything off-screen  */
            bios(FPUTB, 0, c);
            bios(FPUTB, 0, c >> 8);
            px = px + 1;
        }
        py = py + 1;
    }
    if (bios(FCLOSE, 0, 0) & 256) { puts("?Disk full"); return 1; }
    return 0;
}

int main() {
    int a1; int a2; int a3; int a4; int rd;
    ap = argstr();
    skipsp();
    if (*ap == 0 || *ap == 13 ||
        (*ap == '-' && (*(ap + 1) == 'h' || *(ap + 1) == 'H'))) {
        usage();
        return 0;
    }
    if (gpresent() == 0) { puts("?No display"); return 1; }
    rd = 0;
    if (*ap == 'r' || *ap == 'R') {         /* the READ verb (draw starts */
        rd = 1;                             /*   with a number)           */
        while (*ap != 32 && *ap != 0 && *ap != 13) { ap = ap + 1; }
    }
    a1 = anum(); if (anum_ok == 0) { usage(); return 1; }
    a2 = anum(); if (anum_ok == 0) { usage(); return 1; }
    a3 = 0; a4 = 0;
    if (rd) {
        a3 = anum(); if (anum_ok == 0) { usage(); return 1; }
        a4 = anum(); if (anum_ok == 0) { usage(); return 1; }
    }
    skipsp();
    if (abspath(path, ap) == 0) { usage(); return 1; }
    if (rd) { return grab(a1, a2, a3, a4); }
    return draw(a1, a2);
}
