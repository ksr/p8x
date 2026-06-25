/* tail.c — print the last N lines of a file (or stdin). Unix `tail`.
 *
 *     TAIL file            last 10 lines of file
 *     TAIL -5 file         last 5 lines
 *     cmd | TAIL           last 10 lines of a pipe
 *
 * Reads a named file if given (opened like cat), else stdin. Keeps the last N
 * lines in a ring buffer (N defaults to 10, clamped to 1..20), then prints them
 * in order at EOF. Lines are capped at 127 chars; CR is dropped, LF ends a line.
 */
char path[80];
int fromfile;
char buf[2560];                              /* 20 slots x 128 bytes (ring) */

int nextc() {
    int c;
    if (fromfile) {
        c = bios(0x0127, 0, 0);
        if (c & 256) { return 65535; }
        return c & 255;
    }
    return getchar();
}

int openarg(char *a) {                        /* 0=stdin, 1=opened, 2=not found */
    int i;
    int j;
    if (*a == 0 || *a == 13) { return 0; }
    i = 0;
    if (*a != '/') {
        bios(0x4003, path, 0);
        while (path[i] != 0) { i = i + 1; }
        if (i > 0 && path[i - 1] != '/') { path[i] = '/'; i = i + 1; }
    }
    j = 0;
    while (a[j] != 0 && a[j] != 13 && a[j] != 32) {
        path[i] = a[j]; i = i + 1; j = j + 1;
    }
    path[i] = 0;
    bios(0x0133, path, 0);
    if (bios(0x0124, 0xE000, 0) & 256) { return 2; }
    return 1;
}

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
    if (*a == '-') {
        a = a + 1;
        n = 0;
        while (*a >= 48 && *a <= 57) { n = n * 10 + (*a - 48); a = a + 1; }
        while (*a == 32) { a = a + 1; }
    }
    if (n < 1) { n = 1; }
    if (n > 20) { n = 20; }

    fromfile = 0;
    r = openarg(a);
    if (r == 2) { puts("tail: not found"); return 1; }
    if (r == 1) { fromfile = 1; }

    col = 0;                                  /* fill the ring */
    slot = 0;
    total = 0;
    c = nextc();
    while (c != 65535) {
        if (c == 10) {                        /* end of line -> close the slot */
            buf[slot * 128 + col] = 0;
            slot = slot + 1; if (slot >= n) { slot = 0; }
            total = total + 1;
            col = 0;
        } else {
            if (c != 13 && col < 127) { buf[slot * 128 + col] = c; col = col + 1; }
        }
        c = nextc();
    }
    if (col > 0) {                            /* a final line with no trailing LF */
        buf[slot * 128 + col] = 0;
        slot = slot + 1; if (slot >= n) { slot = 0; }
        total = total + 1;
    }

    count = total; if (count > n) { count = n; }   /* how many to print */
    base = 0; if (total > n) { base = slot; }      /* oldest still held */
    while (count > 0) {
        col = 0;
        while (buf[base * 128 + col] != 0) { putchar(buf[base * 128 + col]); col = col + 1; }
        putchar(10);
        base = base + 1; if (base >= n) { base = 0; }
        count = count - 1;
    }
    return 0;
}
