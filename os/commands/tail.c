/* tail.c — print the last N lines of a file (or stdin). Unix `tail`.
 *
 *     TAIL file            last 10 lines of file
 *     TAIL -5 file         last 5 lines
 *     cmd | TAIL           last 10 lines of a pipe
 *
 * Reads a named file if given (opened like cat), else stdin. Keeps the last N
 * lines in a ring buffer (N defaults to 10, clamped to 1..40), then prints them
 * in order at EOF. Lines are capped at 255 chars; CR is dropped, LF ends a line.
 */
//#use stdin   /* path[80], fromfile, nextc(), openarg() */
//#use err     /* eputs(): errors -> console, never into a redirect/pipe */
char buf[10240];                            /* 40 slots x 256 bytes (ring) */
                                            /* Each slot holds one NUL-terminated line; slot i lives at
                                             * buf[i*256 .. i*256+255]. Only the first N slots are used
                                             * (N clamped to 1..40), but the 256-byte stride is fixed so
                                             * indexing stays buf[slot*256 + col] regardless of N. */

/* main — TAIL entry point.
 * Parses an optional -N count and optional filename from the command line,
 * streams the input through a size-N ring of line slots keeping only the most
 * recent N lines, then prints them oldest-first at EOF.
 * No args (params come from argstr()); returns 0 on success, 1 if the named
 * file is missing. nextc()/openarg() come from the stdin lib (//#use stdin). */
int main() {
    char *a;
    int n;
    int c;
    int r;
    int col;
    int slot;
    int total;
    int count;
    int base;

    n = 10;
    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H')) {
        puts("usage: TAIL [-N] [file]   last N lines (default 10), file or stdin");
        return 0;
    }
    if (*a == '-') {                          /* -N: parse the digits after the dash as the line count */
        a = a + 1;
        n = 0;
        while (*a >= 48 && *a <= 57) { n = n * 10 + (*a - 48); a = a + 1; }  /* 48='0', 57='9' */
        while (*a == 32) { a = a + 1; }
    }
    if (n < 1) { n = 1; }
    if (n > 40) { n = 40; }

    fromfile = 0;
    r = openarg(a);
    if (r == 2) { eputs("tail: not found"); return 1; }   /* error -> console: stdout may be a redirect/pipe */
    if (r == 1) { fromfile = 1; }

    col = 0;                                  /* fill the ring */
    slot = 0;
    total = 0;
    c = nextc();
    while (c != 65535) {                      /* 65535 = nextc()'s 16-bit EOF sentinel */
        if (c == 10) {                        /* LF: end of line -> NUL-terminate and advance the ring */
            buf[slot * 256 + col] = 0;
            slot = slot + 1; if (slot >= n) { slot = 0; }  /* wrap; overwrites the oldest held line */
            total = total + 1;                /* total counts every line seen, not just the N kept */
            col = 0;
        } else {
            /* Drop CR (13); store any other byte until the 255-char cap (leaving room for the NUL). */
            if (c != 13 && col < 255) { buf[slot * 256 + col] = c; col = col + 1; }
        }
        c = nextc();
    }
    if (col > 0) {                            /* a final line with no trailing LF */
        buf[slot * 256 + col] = 0;
        slot = slot + 1; if (slot >= n) { slot = 0; }
        total = total + 1;
    }

    /* Print phase. If fewer than N lines arrived, print them all starting at
     * slot 0. Once the ring has wrapped (total > n), `slot` points at the slot
     * about to be reused next — i.e. the oldest surviving line — so start there
     * and walk forward N slots with wraparound. */
    count = total; if (count > n) { count = n; }   /* how many to print */
    base = 0; if (total > n) { base = slot; }      /* oldest still held */
    while (count > 0) {
        col = 0;
        while (buf[base * 256 + col] != 0) { putchar(buf[base * 256 + col]); col = col + 1; }
        putchar(10);
        base = base + 1; if (base >= n) { base = 0; }
        count = count - 1;
    }
    return 0;
}
