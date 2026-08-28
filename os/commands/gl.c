/* gl.c -- speak the graphics language from the shell (stage 10d,
 * STAGE10-DESIGN.md).
 *
 *     GL <command line>       one ASCII GL line, e.g. GL DRAW3 90,-90,300
 *     GL <file>               stream a .gl file's bytes to the card
 *
 * If the first word names a readable file, its bytes stream to the GL
 * port VERBATIM -- the file carries its own CA/CX, so it may be ASCII
 * text, raw hex opcodes, or a mix (the PG-640A manual's house.pga
 * workflow, on a P8X disk). Otherwise the whole argument line is sent
 * as ONE ASCII command line, wrapped "CA " ... " CX " so the card is
 * back in hex mode afterwards (every other tool assumes hex).
 *
 *     GL WINDOW -120 120 -120 120
 *     GL COLOR 31 0 0 PRMFIL 1 POLY3 3 -80 -80 300 80 -80 300 0 40 420
 *     GL CLRUN 0                     replay the scene list
 *     GL /demo.gl                    play a scene file
 *
 * Errors the card queues (see man gl) are drained and reported after
 * the stream, one line per code. */
char path[80];

//#use apath   /* abspath(out, arg): path word -> absolute, CWD-relative */
//#use abi     /* FRESOLVE/FOPEN/FGETB/FCLOSE, RDBUF                     */
//#use gfx

//#define GLID   0xFF54  /* GL presence probe: 'G' when fitted            */
//#define GLDATA 0xFF50  /* the command FIFO, one byte at a time          */
//#define GLSTAT 0xFF51  /* bit7 full, bit6 busy, bit1 error, bit0 rb     */
//#define GLERR  0xFF53  /* pop one error byte (0 = none)                 */
//#define GLRB   0xFF52  /* pop one read-back byte (stage 10e)            */

char *ap;

int glb(int v) {
    while (peek(GLSTAT) & 128) { }
    poke(GLDATA, v);
    return 0;
}

int hxd(int d) {
    if (d < 10) { putchar(48 + d); } else { putchar(55 + d); }
    return 0;
}

int drain() {
    int e; int bad; int n; int v;
    /* pop read-back bytes WHILE waiting for idle: a CLRD bigger than
     * the card's 32-byte RB FIFO stalls the walker until we drain, so
     * waiting for bit6 first would deadlock. Bytes print as hex, 16
     * per line (FLAGRD/MATXRD words are little-endian pairs). */
    n = 0;
    v = 1;
    while (v) {
        if (peek(GLSTAT) & 1) {
            e = peek(GLRB);
            if (n == 0) { putchar('R'); putchar('B'); putchar(':'); }
            putchar(32);
            hxd((e / 16) & 15);
            hxd(e & 15);
            n = n + 1;
            if (n == 16) { putchar(10); n = 0; }
        }
        else { if ((peek(GLSTAT) & 64) == 0) { v = 0; } }
    }
    if (n) { putchar(10); }
    bad = 0;
    e = peek(GLERR);
    while (e) {
        bad = 1;
        if (e == 1) { puts("?GL: unknown command"); }
        else { if (e == 2) { puts("?GL: bad parameter"); }
        else { if (e == 5) { puts("?GL: list op out of place"); }
        else { if (e == 6) { puts("?GL: no such list"); }
        else { if (e == 7) { puts("?GL: list full"); }
        else { puts("?GL: error"); } } } } }
        e = peek(GLERR);
    }
    return bad;
}

int main() {
    int c; int n;
    ap = argstr();
    while (*ap == 32) { ap = ap + 1; }
    if (*ap == 0 || *ap == 13 ||
        (*ap == '-' && (*(ap + 1) == 'h' || *(ap + 1) == 'H'))) {
        puts("usage: GL <command line>   one ASCII GL line (see man gl)");
        puts("       GL <file>           stream a .gl file to the card");
        return 0;
    }
    if (gpresent() == 0) { puts("?No display"); return 1; }
    if (peek(GLID) != 71) { puts("?No GL engine"); return 1; }
    while (peek(GLERR)) { }              /* drain stale errors */

    /* a single word that resolves as a file? stream it verbatim */
    n = 0;
    while (*(ap + n) != 0 && *(ap + n) != 13 && *(ap + n) != 32) { n = n + 1; }
    if (*(ap + n) == 0 || *(ap + n) == 13) {
        abspath(path, ap);
        bios(FRESOLVE, path, 0);
        if ((bios(FOPEN, RDBUF, 0) & 256) == 0) {
            c = bios(FGETB, 0, 0);
            while ((c & 256) == 0) {
                glb(c & 255);
                c = bios(FGETB, 0, 0);
            }
            return drain();
        }
    }
    /* one ASCII command line, mode-wrapped */
    glb(67); glb(65); glb(32);           /* "CA " (works in either mode) */
    while (*ap != 0 && *ap != 13) { glb(*ap); ap = ap + 1; }
    glb(13);                             /* finish the last token */
    glb('C'); glb('X'); glb(32);         /* back to hex */
    return drain();
}
