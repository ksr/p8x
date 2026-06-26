/* lib_stdin.c — shared "file-or-stdin input" helper for /BIN commands.
 *
 * There is no linker and no #include in p8cc, so reusable helpers are shared by
 * concatenation: a command with a `//#use stdin` line gets THIS file spliced in
 * ahead of it by tools/clib.py before p8cc compiles it (see os/run.sh and the
 * c_*_test.sh harness; convention documented in README.md "Shared code").
 *
 * Provides the canonical "open the optional file argument, else read stdin" pair
 * used by grep/head/tail/more/sort/uniq/sed:
 *   path[80], fromfile   globals the command may read (fromfile: 1=file, 0=stdin)
 *   nextc()              next input byte, or 65535 at EOF (file stream or stdin)
 *   openarg(a)           open the file word `a` (CWD-relative or absolute):
 *                          0 = none given (use stdin)
 *                          1 = opened (read stream at $FC00; sets nothing else)
 *                          2 = not found
 *
 * Stays inside the native p8cc.c subset (so commands still build on BOTH
 * compilers): no ++/--, declarations at the top of each function, and the
 * callees are defined before any caller (this file is spliced ABOVE main()).
 *
 * BIOS/OS calls: FGETB $0127, FRESOLVE $0133, FOPEN $0124, SYS_GETCWD $4003.
 */
char path[80];                               /* absolute path of the file arg */
int fromfile;                                /* 1 = read the file stream, 0 = stdin */

int nextc() {                                /* next byte, or 65535 at EOF */
    int c;
    if (fromfile) {
        c = bios(0x0127, 0, 0);              /* FGETB: A | carry<<8 */
        if (c & 256) { return 65535; }       /* carry = end of file */
        return c & 255;
    }
    return getchar();                        /* SYS_GETC; 65535 at EOF */
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
    /* Read buffer at $FC00 — just below the stack page ($FE00), so it clears even
     * the largest command's code/globals (they grow up from $B000). $E000 was too
     * low: a big build (e.g. sed/diff on the native p8cc.c) overran it. */
    if (bios(0x0124, 0xFC00, 0) & 256) { return 2; }   /* FOPEN; carry = not found */
    return 1;
}
