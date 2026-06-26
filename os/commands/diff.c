/* diff.c — compare two files line by line (a small `diff`).
 *
 *     DIFF OLD.TXT NEW.TXT
 *
 * Reads both files into memory (<=40 lines of <=63 chars each), skips the common
 * leading and trailing lines, and reports the differing middle: lines only in
 * the first file prefixed "< ", lines only in the second prefixed "> ". Prints
 * nothing if the files are identical. This is a *prefix/suffix-anchored* diff
 * (it isolates one changed/inserted block) — not a minimal-edit LCS diff.
 *
 * BIOS: FRESOLVE=$0133, FOPEN=$0124, FGETB=$0127.  OS: SYS_GETCWD=$4003.
 * Read buffer at $FC00 (the two files are read one after the other).
 */
char path[80];
char alines[2560];                           /* 40 x 64 */
char blines[2560];
int na;
int nb;

//#use abspath

int openf(char *a) {                          /* FRESOLVE+FOPEN; 1 ok, 0 not found */
    bios(0x0133, path, 0);
    if (bios(0x0124, 0xFC00, 0) & 256) { return 0; }
    return 1;
}

int loadlines(char *buf) {                    /* read the open stream into buf; line count */
    int n;
    int col;
    int c;
    n = 0;
    col = 0;
    c = bios(0x0127, 0, 0);
    while ((c & 256) == 0 && n < 40) {
        c = c & 255;
        if (c == 10) { buf[n * 64 + col] = 0; n = n + 1; col = 0; }
        else { if (c != 13 && col < 63) { buf[n * 64 + col] = c; col = col + 1; } }
        c = bios(0x0127, 0, 0);
    }
    if (col > 0 && n < 40) { buf[n * 64 + col] = 0; n = n + 1; }
    return n;
}

int leq(char *x, int xi, char *y, int yi) {   /* are line xi of x and yi of y equal? */
    int i;
    int a;
    int b;
    i = 0;
    while (1) {
        a = x[xi * 64 + i] & 255;
        b = y[yi * 64 + i] & 255;
        if (a != b) { return 0; }
        if (a == 0) { return 1; }
        i = i + 1;
    }
}

int emit(char *tag, char *buf, int li) {      /* print "<tag> line\n" */
    int i;
    i = 0;
    while (tag[i] != 0) { putchar(tag[i]); i = i + 1; }
    i = 0;
    while (buf[li * 64 + i] != 0) { putchar(buf[li * 64 + i]); i = i + 1; }
    putchar(10);
    return 0;
}

int main() {
    char *a;
    int n;
    int p;
    int sa;
    int sb;
    int i;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: DIFF file1 file2   show differing lines (< file1, > file2)");
        return 0;
    }
    n = abspath(path, a);                     /* file 1 */
    a = a + n;
    while (*a == 32) { a = a + 1; }
    if (openf(path) == 0) { puts("diff: file1 not found"); return 1; }
    na = loadlines(alines);

    if (*a == 0 || *a == 13) { puts("usage: DIFF file1 file2"); return 1; }
    abspath(path, a);                         /* file 2 */
    if (openf(path) == 0) { puts("diff: file2 not found"); return 1; }
    nb = loadlines(blines);

    p = 0;                                     /* common prefix */
    while (p < na && p < nb && leq(alines, p, blines, p)) { p = p + 1; }
    sa = na;                                   /* common suffix */
    sb = nb;
    while (sa > p && sb > p && leq(alines, sa - 1, blines, sb - 1)) {
        sa = sa - 1; sb = sb - 1;
    }
    if (p == sa && p == sb) { return 0; }      /* identical */

    i = p;
    while (i < sa) { emit("< ", alines, i); i = i + 1; }
    i = p;
    while (i < sb) { emit("> ", blines, i); i = i + 1; }
    return 0;
}
