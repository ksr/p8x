/* wc.c — count lines, words, and bytes of a file, a glob, or stdin (Unix `wc`).
 *
 *     RUN /BIN/WC.BIN FILE          -> "L W B"  (lines words bytes)
 *     RUN /BIN/WC.BIN *.LOG         -> combined count over every matching file
 *     RUN /BIN/WC.BIN <FILE         -> from a stdin redirect
 *     cmd | RUN /BIN/WC.BIN         -> counts the pipe
 *  (and, via implicit RUN + PATH, simply `WC FILE`, `WC *.LOG`, or `… | WC`).
 *
 * A stdin->stdout filter built on the shared open-input helper (lib_stdin): a
 * file or glob argument is read via that (a glob is read as ONE concatenated
 * stream — combined totals, like `CAT *.LOG | WC`), else it reads stdin. Counts
 * newlines (LF) as lines and whitespace-delimited runs as words.
 *
 * Counts are 24-bit — a file may be up to 16 MB now. p8cc's int is 16-bit, so
 * each counter is a 3-byte little-endian array incremented by inc24() and printed
 * by put24() (a byte-wise divmod10, like dir's size column).
 *
 * OS: getchar() is SYS_GETC; EOF is 65535. With no arg/`<file`/pipe, stdin is
 * the console and Ctrl-D ends input.
 */
//#use stdin   /* path[80], fromfile, nextc(), openarg() — file/glob/stdin input */

char num24[3];                                /* scratch 24-bit for the printer */
char dg[10];                                  /* digit buffer */
char clin[3];                                 /* line count (24-bit LE) */
char cwrd[3];                                 /* word count */
char cbyt[3];                                 /* byte count */

/* dm10: num24 /= 10 in place, return remainder 0..9 (p8cc int is 16-bit, so a
 * 24-bit value is long-divided a byte at a time; cur = rem*256 + byte < 2560). */
int dm10() {
    int rem;
    int i;
    int cur;
    int n;
    rem = 0;
    i = 2;
    n = 3;                                     /* count down: p8cc's >= 0 is unsigned */
    while (n != 0) {
        cur = rem * 256 + (num24[i] & 255);
        num24[i] = cur / 10;
        rem = cur - (cur / 10) * 10;
        i = i - 1;
        n = n - 1;
    }
    return rem;
}

/* nz24: is num24 nonzero? Returns 1 if any of its 3 bytes is set, else 0.
 * put24 uses it as the "more digits remain" test after the first digit. */
int nz24() {
    if (num24[0] != 0) { return 1; }
    if (num24[1] != 0) { return 1; }
    if (num24[2] != 0) { return 1; }
    return 0;
}

/* inc24: 24-bit increment of the 3-byte counter p. */
int inc24(char *p) {
    int v;
    v = (p[0] & 255) + 1;
    p[0] = v & 255;
    if (v >= 256) {                            /* v is 1..256, never negative */
        v = (p[1] & 255) + 1;
        p[1] = v & 255;
        if (v >= 256) { p[2] = (p[2] & 255) + 1; }
    }
    return 0;
}

/* put24: print the 3-byte counter p as an unsigned decimal (no padding). */
int put24(char *p) {
    int nd;
    num24[0] = p[0] & 255;
    num24[1] = p[1] & 255;
    num24[2] = p[2] & 255;
    nd = 0;
    dg[nd] = 48 + dm10();                       /* at least one digit (handles 0) */
    nd = nd + 1;
    while (nz24()) {
        dg[nd] = 48 + dm10();
        nd = nd + 1;
    }
    while (nd != 0) { nd = nd - 1; putchar(dg[nd]); }
    return 0;
}

/* main: parse the optional arg, open the input, then scan it byte by byte,
 * tallying bytes/lines/words into the three 24-bit counters, and print
 * "lines words bytes". A word is a maximal run of non-whitespace: inword
 * tracks whether we're mid-word so each run is counted once, on its first
 * non-space char. Whitespace = space/tab/LF/CR; only LF bumps the line count.
 * Returns 0 on success, 1 if the file/glob was not found. */
int main() {
    char *arg;
    int c;
    int r;
    int inword;

    arg = argstr();
    while (*arg == 32) { arg = arg + 1; }
    if (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H')) {
        puts("usage: WC [file|glob]   count lines words bytes (file/glob or stdin)");
        return 0;
    }

    fromfile = 0;
    r = openarg(arg);                         /* file/glob, else stdin */
    if (r == 2) { puts("wc: not found"); return 1; }
    if (r == 1) { fromfile = 1; }

    clin[0] = 0; clin[1] = 0; clin[2] = 0;
    cwrd[0] = 0; cwrd[1] = 0; cwrd[2] = 0;
    cbyt[0] = 0; cbyt[1] = 0; cbyt[2] = 0;
    inword = 0;
    c = nextc();
    while (c != 65535) {
        inc24(cbyt);
        if (c == 10) { inc24(clin); }
        if (c == 32 || c == 9 || c == 10 || c == 13) {
            inword = 0;
        } else {
            if (inword == 0) { inc24(cwrd); inword = 1; }
        }
        c = nextc();
    }
    put24(clin); putchar(32);
    put24(cwrd); putchar(32);
    put24(cbyt); putchar(10);
    return 0;
}
