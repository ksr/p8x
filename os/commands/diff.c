/* diff.c — compare two files line by line (a small `diff`).
 *
 *     DIFF OLD.TXT NEW.TXT
 *
 * Reads both files into memory (<=96 lines of <=79 chars each (rev-D TPA; was 40 x 63)), skips the common
 * leading and trailing lines, and reports the differing middle: lines only in
 * the first file prefixed "< ", lines only in the second prefixed "> ". Prints
 * nothing if the files are identical. This is a *prefix/suffix-anchored* diff
 * (it isolates one changed/inserted block) — not a minimal-edit LCS diff.
 *
 * BIOS: FRESOLVE=$0133, FOPEN=$0124, FGETB=$0127.  OS: SYS_GETCWD=$2003.
 * Read buffer at $FC00 (the two files are read one after the other).
 */
/* Line storage is a fixed 2-D grid flattened into one array: line L, column C
 * lives at buf[L*80 + C]. Each row holds up to 79 chars plus a NUL terminator,
 * so 96 rows * 80 bytes = 7680. na/nb hold the actual line counts after load. */
char path[80];                               /* scratch for the resolved path of the file being opened */
char alines[7680];                           /* file 1 lines, 96 rows x 80 bytes */
char blines[7680];                           /* file 2 lines, same layout */
int na;                                       /* number of lines read from file 1 */
int nb;                                       /* number of lines read from file 2 */

//#use apath
//#use abi     /* named BIOS/OS addresses: FOPEN, FGETB, SYS_GETCWD, RDBUF, ... */

/* openf: resolve the path in the global `path` and open it for reading.
 * The `a` parameter is unused (the routine reads the global `path`).
 * FRESOLVE turns the (already absolute) path into a directory/file handle;
 * FOPEN then opens it into the shared read buffer RDBUF ($FC00).
 * FOPEN signals failure by setting bit 8 (the 256 flag) of its return.
 * Returns 1 on success, 0 if the file was not found / could not open.
 * Clobbers P1/P2 via the BIOS calls. */
int openf(char *a) {                          /* FRESOLVE+FOPEN; 1 ok, 0 not found */
    bios(FRESOLVE, path, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { return 0; }
    return 1;
}

/* loadlines: read the currently-open file byte by byte into the line grid `buf`.
 * FGETB returns the next byte, or a value with bit 8 (256) set at end-of-file.
 * LF (10) terminates a line: NUL-terminate the row and advance to the next.
 * CR (13) is dropped so CRLF files load cleanly. Any byte past column 79 is
 * discarded (line truncated to fit the 79-char row). Reading stops at EOF or
 * once 96 rows are filled (excess lines are silently ignored). A final line
 * with no trailing newline is still counted (the `col > 0` tail check).
 * Returns the number of lines stored. Clobbers P1/P2 via FGETB. */
int loadlines(char *buf) {                    /* read the open stream into buf; line count */
    int n;                                    /* current/total line count */
    int col;                                  /* column within the current line */
    int c;                                    /* byte from FGETB (bit 8 = EOF) */
    n = 0;
    col = 0;
    c = bios(FGETB, 0, 0);
    while ((c & 256) == 0 && n < 96) {
        c = c & 255;                          /* strip the EOF flag bit to get the raw byte */
        if (c == 10) { buf[n * 80 + col] = 0; n = n + 1; col = 0; }
        else { if (c != 13 && col < 79) { buf[n * 80 + col] = c; col = col + 1; } }
        c = bios(FGETB, 0, 0);
    }
    if (col > 0 && n < 96) { buf[n * 80 + col] = 0; n = n + 1; }  /* flush unterminated last line */
    return n;
}

/* leq: compare row xi of grid x against row yi of grid y for exact equality.
 * Walks both NUL-terminated rows in lockstep; bytes are masked to 8 bits so a
 * high-bit char never sign-mismatches. Returns 1 if equal, 0 at first mismatch. */
int leq(char *x, int xi, char *y, int yi) {   /* are line xi of x and yi of y equal? */
    int i;
    int a;
    int b;
    i = 0;
    while (1) {
        a = x[xi * 80 + i] & 255;
        b = y[yi * 80 + i] & 255;
        if (a != b) { return 0; }
        if (a == 0) { return 1; }
        i = i + 1;
    }
}

/* emit: print the tag string (e.g. "< " or "> ") followed by row li of grid
 * buf and a trailing newline. Used to report one differing line. */
int emit(char *tag, char *buf, int li) {      /* print "<tag> line\n" */
    int i;
    i = 0;
    while (tag[i] != 0) { putchar(tag[i]); i = i + 1; }
    i = 0;
    while (buf[li * 80 + i] != 0) { putchar(buf[li * 80 + i]); i = i + 1; }
    putchar(10);
    return 0;
}

/* main: parse "DIFF file1 file2", load both files, then anchor on the common
 * prefix and suffix and print only the middle block that differs.
 * `p`  = count of identical leading lines (common prefix).
 * sa/sb = end index (exclusive) of each file's differing region; the trailing
 *         common suffix has already been peeled off below them.
 * So [p, sa) are file-1-only lines ("< ") and [p, sb) are file-2-only ("> ").
 * Exits early with nothing printed when the files are identical. */
int main() {
    char *a;                                  /* cursor into the argument string */
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
    n = abspath(path, a);                     /* file 1: write absolute path, n = chars of arg consumed */
    a = a + n;                                /* advance past the first filename token */
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
