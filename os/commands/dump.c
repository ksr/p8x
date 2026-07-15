/* dump.c — hex-dump memory: DUMP addr
 *
 *     DUMP 6A00        show 256 bytes from $6A00 (16 rows of 16), hex + ASCII
 *
 * Prints one 256-byte block, then waits for a console key: "." returns to the
 * shell, any other key shows the next block. addr is hexadecimal. The
 * counterpart to DEP. Formerly an OS built-in; now a /bin program -- it needs
 * only raw memory reads (peek) and a console key (BIOS CONIN), so it does not
 * belong in the resident kernel.
 *
 * Each row is:  AAAA: bb bb ... bb  cccccccccccccccc
 * where non-printable bytes ($20..$7E outside) show as '.'.
 */
//#use abi     /* named BIOS/OS addresses: FOPEN, FGETB, SYS_GETCWD, RDBUF, ... */

/* Uses only leaf helpers: argstr() -> command-line tail, peek() -> raw byte at
 * a 16-bit address, putchar()/puts() -> console out, and bios(CONIN,..) for a
 * blocking key read. No file I/O, so nothing here clobbers P1/P2 across calls. */

char *HD = "0123456789ABCDEF";                 /* hex-digit lookup table */

/* ph2/ph4: print a byte / a 16-bit word as hex digits. */
int ph2(int v) { putchar(HD[(v >> 4) & 15]); putchar(HD[v & 15]); return 0; }
int ph4(int v) { ph2((v >> 8) & 255); ph2(v & 255); return 0; } /* high byte first */

/* hx: value of one hex digit (0..15), or 99 if not a hex digit. */
int hx(int c) {
    if (c >= '0' && c <= '9') { return c - '0'; }
    if (c >= 'A' && c <= 'F') { return c - 'A' + 10; }
    if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
    return 99;                              /* p8cc compares UNSIGNED: use an
                                             * out-of-range sentinel, not -1 */
}

int main() {
    char *a;
    int addr;
    int any;
    int d;
    int row;
    int i;
    int b;
    int k;

    a = argstr();                            /* command tail after "DUMP" */
    while (*a == 32) { a = a + 1; }          /* skip leading spaces (32 = ' ') */
    /* Empty arg, a bare CR (13), or "-h"/"-H" -> print usage and exit 0. */
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: DUMP addr   show 256 bytes from hex address addr");
        return 0;
    }

    /* Parse the hex address: fold digits MSB-first (addr*16 + digit) until a
     * non-hex char stops the run. hx() returns 99 for non-digits, so the
     * (d < 16) test ends the loop. `any` guards against a zero-digit arg. */
    addr = 0;
    any = 0;
    d = hx(*a);
    while (d < 16) {
        addr = addr * 16 + d;
        a = a + 1;
        any = 1;
        d = hx(*a);
    }
    if (any == 0) { puts("dump: bad address"); return 1; }

    while (1) {                              /* one 256-byte block per page */
        row = 0;
        while (row < 16) {
            ph4(addr);                       /* "AAAA: " */
            putchar(':');
            putchar(32);
            i = 0;                           /* 16 hex bytes */
            while (i < 16) {
                ph2(peek(addr + i) & 255);
                putchar(32);
                i = i + 1;
            }
            putchar(32);
            i = 0;                           /* 16 ASCII bytes */
            while (i < 16) {
                b = peek(addr + i) & 255;
                if (b >= 32 && b < 127) { putchar(b); }
                else { putchar('.'); }
                i = i + 1;
            }
            putchar(13);
            putchar(10);
            addr = addr + 16;
            row = row + 1;
        }
        k = bios(CONIN, 0, 0) & 255;        /* CONIN: '.' quits, else next page */
        if (k == '.') { return 0; }
    }
    return 0;
}
