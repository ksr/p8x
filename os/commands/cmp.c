/* cmp.c — compare two files byte for byte.
 *
 *     cmp file1 file2
 *
 * Silent (and exit 0) when the files are identical. Otherwise prints the offset
 * of the first difference:
 *     cmp: files differ: byte N, line M
 * or, when one file is a prefix of the other:
 *     cmp: EOF on file1   (file2 is longer)
 *     cmp: EOF on file2   (file1 is longer)
 *
 * The first file is read into a buffer (up to 8 KB), then the second is streamed
 * and compared against it. Both are read one after the other through the single
 * BIOS read stream. A companion to diff (which is line-oriented).
 */
//#use apath   /* abspath(dst, src): CWD-prefix a relative path, return length */
//#use abi     /* FRESOLVE, FOPEN, FGETB, RDBUF ($FC00) */

char path[80];
char b1[8192];                               /* file 1 contents */
int  n1;                                     /* file 1 length */

/* openf: resolve the global `path` and open it for reading through the BIOS
 * read stream. FRESOLVE walks the pathname; FOPEN(RDBUF) attaches it to the
 * shared $FC00 read buffer. Returns 1 on success, 0 if not found. The FOPEN
 * result carries its status in bit 8 (the 256 flag = the BIOS's "error/EOF"
 * marker), so a set 256 bit means the open failed. Ignores the `a` argument;
 * the caller stages the name in `path` first. Clobbers P1/P2 via the syscalls. */
int openf(char *a) {                          /* FRESOLVE+FOPEN; 1 ok, 0 not found */
    bios(FRESOLVE, path, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { return 0; }
    return 1;
}

/* pstr: write a NUL-terminated string to stdout, no trailing newline (unlike
 * puts, which appends one). Used to build the "files differ" line piecewise. */
int pstr(char *s) { int i; i = 0; while (s[i] != 0) { putchar(s[i]); i = i + 1; } return 0; }

/* pnum: print a non-negative decimal integer. Digits are generated least-
 * significant first into d[] (v - (v/10)*10 is v%10, since p8cc has no % here),
 * then emitted in reverse. d[8] is ample: a 16-bit int is at most 5 digits. */
int pnum(int v) {                             /* print a non-negative decimal */
    char d[8];
    int n;
    if (v == 0) { putchar('0'); return 0; }
    n = 0;
    while (v != 0) { d[n] = (v - (v / 10) * 10) + '0'; n = n + 1; v = v / 10; }
    while (n != 0) { n = n - 1; putchar(d[n]); }
    return 0;
}

/* main: parse "file1 file2" from the command tail, slurp file1 into b1[], then
 * stream file2 and compare byte-by-byte. Exit 0 (silent) if identical, else 1
 * after reporting the first difference or which file hit EOF first.
 * FGETB returns the next byte in the low 8 bits; bit 8 (the 256 flag) set means
 * end-of-file, so `(c & 256) == 0` is the "got a real byte" loop condition. */
int main() {
    char *a;
    int n;
    int c;
    int off;
    int line;

    a = argstr();                             /* raw command tail after "CMP" */
    while (*a == 32) { a = a + 1; }           /* skip leading spaces (32 = ' ') */
    /* No args, bare CR (13), or a -h/-H help flag -> print usage and succeed. */
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: CMP file1 file2   report the first differing byte (silent if equal)");
        return 0;
    }

    /* Parse file1's name into `path`; abspath returns the consumed length so we
     * can advance `a` past it to the second argument. */
    n = abspath(path, a);                     /* file 1 */
    a = a + n;
    while (*a == 32) { a = a + 1; }           /* skip spaces before file2 */
    if (openf(path) == 0) { puts("cmp: file1 not found"); return 1; }
    n1 = 0;                                    /* slurp file 1 into b1 */
    c = bios(FGETB, 0, 0);
    while ((c & 256) == 0) {
        /* Keep counting past 8192 even though we stop storing, so the
         * over-size check below can detect a too-large file. */
        if (n1 < 8192) { b1[n1] = c & 255; }
        n1 = n1 + 1;
        c = bios(FGETB, 0, 0);
    }
    /* b1[] holds only 8192 bytes; a longer file1 can't be compared reliably. */
    if (n1 > 8192) { puts("cmp: file1 too large (max 8K)"); return 1; }

    if (*a == 0 || *a == 13) { puts("usage: CMP file1 file2"); return 1; }
    abspath(path, a);                         /* file 2 */
    if (openf(path) == 0) { puts("cmp: file2 not found"); return 1; }

    off = 0;                                   /* byte offset into file2 / b1 */
    line = 1;                                  /* 1-based line of current byte */
    c = bios(FGETB, 0, 0);
    while ((c & 256) == 0) {
        /* Ran past the end of the buffered file1 while file2 still has bytes:
         * file1 is a proper prefix of file2, so file1 hit EOF first. */
        if (off >= n1) { puts("cmp: EOF on file1"); return 1; }   /* file2 longer */
        if ((b1[off] & 255) != (c & 255)) {
            pstr("cmp: files differ: byte ");
            pnum(off + 1);
            pstr(", line ");
            pnum(line);
            putchar(10);
            return 1;
        }
        if ((b1[off] & 255) == 10) { line = line + 1; }  /* count newlines (LF=10) */
        off = off + 1;
        c = bios(FGETB, 0, 0);
    }
    /* file2 ended but file1 still has unread bytes: file2 is a proper prefix. */
    if (off < n1) { puts("cmp: EOF on file2"); return 1; }        /* file1 longer */
    return 0;                                                     /* identical: silent */
}
