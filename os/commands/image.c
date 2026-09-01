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
 * SINGLE-INTERFACE since 2026-09-01: both verbs speak the GL port only.
 * Draw: FGETB the header, validate ("?NOT P8I" on bad magic/version/depth,
 * "?No file" if missing), then ONE GL BLIT PER ROW with the file bytes
 * streamed VERBATIM into the FIFO (P8I rows are already the BLIT payload);
 * a short file pads the row in flight with zeros -- the walker must get
 * every byte it is owed -- then reports ?NOT P8I. Grab: corners self-sort
 * like BOX; each pixel is a PIXRD verb answered through the read-back
 * FIFO, written little-endian after a 10-byte header. An existing file of
 * the same name is REPLACED (FDELETE then rewrite). Grabs read the DRAW
 * page; PGSYNC is issued first so a grab always captures what the panel
 * shows. NOTE this shell command keeps its SCREEN coordinates (top-left
 * anchor, y down) -- unlike BASIC's IMAGE statement, which is window-
 * space; the flip happens here, per row / per probe. */
char path[80];

//#use apath   /* abspath(out, arg): path word -> absolute, CWD-relative */
//#use abi     /* FRESOLVE/FOPEN/FGETB/FWOPEN/FPUTB/FCLOSE/FDELETE, RDBUF */
//#use gfx     /* gpresent/gcolor/gpixelw/gpixelr */

//#define GLID   0xFF54  /* graphics-language probe ('G' when fitted)      */
//#define GLDATA 0xFF50  /* the command FIFO (BLIT payload streams here)   */
//#define GLSTAT 0xFF51  /* bit7 FIFO full, bit6 busy, bit0 read-back      */
//#define GLRB   0xFF52  /* pop one read-back byte (PIXRD's reply)         */

/* The loops below poke the GL port RAW instead of layering through the
 * library (p8cc call frames cost ~500 cycles each); the library still
 * provides gpresent()'s probe+init and the odd helper. */

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

/* push one GL byte with FIFO backpressure (raw: speed) */
int gput(int v) {
    while (peek(GLSTAT) & 128) { }
    poke(GLDATA, v);
    return 0;
}

/* draw the P8I at `path` with its top-left at SCREEN (x,y): one BLIT
 * per row, the file bytes streamed verbatim */
int draw(int x, int y) {
    int w; int h; int py; int n; int lo; int wy;
    bios(FRESOLVE, path, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { puts("?No file"); return 1; }
    if ((bios(FGETB, 0, 0) & 511) != 'P') { puts("?NOT P8I"); return 1; }
    if ((bios(FGETB, 0, 0) & 511) != '8') { puts("?NOT P8I"); return 1; }
    if ((bios(FGETB, 0, 0) & 511) != 'I') { puts("?NOT P8I"); return 1; }
    if ((bios(FGETB, 0, 0) & 511) != 1)   { puts("?NOT P8I"); return 1; }
    lo = bios(FGETB, 0, 0); n = bios(FGETB, 0, 0);
    if ((lo | n) & 256) { puts("?NOT P8I"); return 1; }
    w = (lo & 255) | ((n & 255) << 8);
    lo = bios(FGETB, 0, 0); n = bios(FGETB, 0, 0);
    if ((lo | n) & 256) { puts("?NOT P8I"); return 1; }
    h = (lo & 255) | ((n & 255) << 8);
    if ((bios(FGETB, 0, 0) & 511) != 16) { puts("?NOT P8I"); return 1; }
    bios(FGETB, 0, 0);                       /* reserved byte */
    if (w == 0 || h == 0 || w > 512) { puts("?NOT P8I"); return 1; }
    py = y;
    h = y + h;                               /* absolute end row */
    while (py != h) {
        wy = 271 - py;                       /* this row's window y */
        gput(100);                           /* BLIT x wy w 1 */
        gput(x); gput(x >> 8);
        gput(wy); gput(wy >> 8);
        gput(w); gput(w >> 8);
        gput(1); gput(0);
        n = w + w;                           /* 2*w payload bytes */
        while (n) {
            lo = bios(FGETB, 0, 0);
            if (lo & 256) {                  /* short file: the walker is
                                                owed the rest -- pad with
                                                zeros to keep the stream
                                                in sync, then report */
                while (n) { gput(0); n = n - 1; }
                puts("?NOT P8I");
                return 1;
            }
            gput(lo & 255);
            n = n - 1;
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
    if (peek(GLID) == 71) {                       /* PGSYNC: grab what shows */
        poke(GLDATA, 3);
        while (peek(GLSTAT) & 64) { }             /* wait the verb out */
    }
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
        c = 271 - py;                       /* this row's window y */
        px = x0;
        while (px <= x1) {
            gput(99);                       /* PIXRD px wy: 0 off-screen */
            gput(px); gput(px >> 8);
            gput(c); gput(c >> 8);
            while ((peek(GLSTAT) & 1) == 0) { }
            bios(FPUTB, 0, peek(GLRB));     /* low byte, then high --    */
            while ((peek(GLSTAT) & 1) == 0) { }
            bios(FPUTB, 0, peek(GLRB));     /*   P8I is little-endian    */
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
