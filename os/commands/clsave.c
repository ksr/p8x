/* clsave.c -- save a recorded GL command list to a disk file (stage 10e).
 *
 *     CLSAVE n FILE
 *
 * CLRD n streams the stored list -- a length halfword, then the raw hex
 * command bytes -- into the card's read-back FIFO; this drains it into
 * FILE (the bytes only; the length frames the transfer and is not
 * stored). The file is a pure hex command stream, so it replays as-is:
 *
 *     gl FILE                          draw it now (hex is power-up mode)
 *     gl CLBEG 3  +  gl FILE  +  gl CLEND     ...or re-record it
 *
 * With this, the scene tri built (list 0) or house's list 1 survives
 * power -- record on the card, save to disk, replay any day. The FIFO
 * is small (32 bytes) and the card STALLS when it fills, so the drain
 * loop below is also the flow control. */
char path[80];

//#use apath
//#use gfx
//#use abi

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

/* rbb: one read-back byte; -1 if the card queued an error instead. */
int rbb() {
    int s;
    s = peek(GLSTAT);
    while ((s & 1) == 0) {
        if (s & 2) { return 0 - 1; }
        s = peek(GLSTAT);
    }
    return peek(GLRB) & 255;
}

int main() {
    int n; int c; int len; int i;
    ap = argstr();
    while (*ap == 32) { ap = ap + 1; }
    n = 0 - 1;
    if (*ap >= '0' && *ap <= '9') {
        n = 0;
        while (*ap >= '0' && *ap <= '9') { n = n * 10 + (*ap - '0'); ap = ap + 1; }
    }
    while (*ap == 32) { ap = ap + 1; }
    if (n < 0 || *ap == 0 || *ap == 13) {
        puts("usage: CLSAVE n FILE    save GL command list n (see man clsave)");
        return 0;
    }
    if (gpresent() == 0) { puts("?No display"); return 1; }
    if (peek(GLID) != 71) { puts("?No GL engine"); return 1; }
    while (peek(GLERR)) { }              /* drain stale errors */

    glb(118); glb(n);                    /* CLRD n */
    c = rbb();
    if (c < 0) {
        while (peek(GLERR)) { }
        puts("?No such list");
        return 1;
    }
    len = c;
    c = rbb();
    len = len + 256 * c;

    abspath(path, ap);
    bios(FRESOLVE, path, 0);
    bios(FWOPEN, 0, 0);
    i = 0;
    c = 0;
    while (i < len && c >= 0) {
        c = rbb();
        if (c >= 0) { bios(FPUTB, 0, c); i = i + 1; }
    }
    bios(FCLOSE, 0, 0);
    while (peek(GLSTAT) & 64) { }
    if (i < len) { puts("?Read-back error"); return 1; }
    putchar('0' + (len / 100) % 10); putchar('0' + (len / 10) % 10);
    putchar('0' + len % 10);
    puts(" bytes saved");
    return 0;
}
