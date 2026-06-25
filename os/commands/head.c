/* head.c — print the first N lines of a file (or stdin). Unix `head`.
 *
 *     HEAD file            first 10 lines of file
 *     HEAD -5 file         first 5 lines
 *     cmd | HEAD           first 10 lines of a pipe
 *     HEAD <file           first 10 lines from a stdin redirect
 *
 * Reads a named file if given (opened like cat: absolute path via SYS_GETCWD +
 * FRESOLVE/FOPEN, buffer at $E000), else stdin. Line count defaults to 10, or
 * -N sets it. A line ends at LF; CR is passed through. EOF = 65535.
 */
char path[80];
int fromfile;

int nextc() {                                /* next byte, or 65535 at EOF */
    int c;
    if (fromfile) {
        c = bios(0x0127, 0, 0);              /* FGETB: A | carry<<8 */
        if (c & 256) { return 65535; }
        return c & 255;
    }
    return getchar();
}

/* openarg: open the file word at a (space-skipped). 0=none(stdin), 1=opened,
 * 2=not found. Builds an absolute path so it resolves against the CWD. */
int openarg(char *a) {
    int i;
    int j;
    if (*a == 0 || *a == 13) { return 0; }
    i = 0;
    if (*a != '/') {
        bios(0x4003, path, 0);               /* SYS_GETCWD */
        while (path[i] != 0) { i = i + 1; }
        if (i > 0 && path[i - 1] != '/') { path[i] = '/'; i = i + 1; }
    }
    j = 0;
    while (a[j] != 0 && a[j] != 13 && a[j] != 32) {
        path[i] = a[j]; i = i + 1; j = j + 1;
    }
    path[i] = 0;
    bios(0x0133, path, 0);                    /* FRESOLVE */
    if (bios(0x0124, 0xE000, 0) & 256) { return 2; }   /* FOPEN; carry = not found */
    return 1;
}

int main() {
    char *a;
    int n;
    int lines;
    int c;
    int r;

    n = 10;
    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H')) {
        puts("usage: HEAD [-N] [file]   first N lines (default 10), file or stdin");
        return 0;
    }
    if (*a == '-') {                          /* -N : a line count */
        a = a + 1;
        n = 0;
        while (*a >= 48 && *a <= 57) { n = n * 10 + (*a - 48); a = a + 1; }
        while (*a == 32) { a = a + 1; }
    }

    fromfile = 0;
    r = openarg(a);
    if (r == 2) { puts("head: not found"); return 1; }
    if (r == 1) { fromfile = 1; }

    lines = 0;
    c = nextc();
    while (c != 65535 && lines < n) {
        putchar(c);
        if (c == 10) { lines = lines + 1; }
        c = nextc();
    }
    return 0;
}
