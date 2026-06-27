/* lib_stdin.c — shared "file(s)-or-stdin input" helper for /BIN commands.
 *
 * There is no linker and no #include in p8cc, so reusable helpers are shared by
 * concatenation: a command with a `//#use stdin` line gets THIS file spliced in
 * ahead of it by tools/clib.py before p8cc compiles it (see os/run.sh and the
 * c_*_test.sh harness; convention documented in README.md "Shared code").
 *
 * Provides the canonical "open the optional file argument, else read stdin" pair
 * used by grep/head/tail/more/sort/uniq/sed/wc:
 *   path[80], fromfile   globals the command may read (fromfile: 1=file, 0=stdin)
 *   nextc()              next input byte, or 65535 at EOF (file stream or stdin)
 *   openarg(a)           open the file word `a` (CWD-relative or absolute):
 *                          0 = none given (use stdin)
 *                          1 = opened (read stream at $FC00)
 *                          2 = not found
 *
 * GLOB: if `a` contains `*`/`?`, openarg expands it (via lib_globx's glob_expand)
 * into every matching file and nextc() reads them back-to-back as ONE stream —
 * so `GREP foo *.C`, `SORT *.TXT`, `WC *.LOG` behave exactly like `CAT *.X | cmd`
 * with no per-command logic. glob_expand points FSDIRBUF at $FA, and FSCAN
 * honours that page, so the per-file path walks don't clobber an open write
 * stream's SBUF (`SORT *.TXT >OUT` works). An empty match set -> "not found" (2).
 *
 * Stays inside the native p8cc.c subset (so commands still build on BOTH
 * compilers): no ++/--, declarations at the top of each function, and the
 * callees are defined before any caller (this file is spliced ABOVE main()).
 *
 * BIOS/OS calls: FGETB $0127, FRESOLVE $0133, FOPEN $0124, SYS_GETCWD $4003.
 */
//#use globx   /* glob_expand(pat,out,maxn); clib.py recursively splices glob too */

char path[80];                               /* absolute path of the current file */
int fromfile;                                /* 1 = read the file stream, 0 = stdin */
char gfiles[1536];                           /* glob expansion: up to 24 paths x 64 */
int gnf;                                     /* glob match count (0 = single/none) */
int gidx;                                    /* index of the file currently open */

/* open_path: open one file word at `a` (space-skipped, CWD-relative or absolute).
 * Builds an absolute path so a relative name resolves against the CWD, then
 * FRESOLVE + FOPEN (read buffer $FC00). Returns 1 opened, 2 not found. */
int open_path(char *a) {
    int i;
    int j;
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
    /* Read buffer at $FC00 — just below the stack page ($FE00), clear of even the
     * largest command's code/globals (they grow up from $7A00). */
    if (bios(0x0124, 0xFC00, 0) & 256) { return 2; }   /* FOPEN; carry = not found */
    return 1;
}

int nextc() {                                /* next byte, or 65535 at EOF */
    int c;
    char *p;
    if (fromfile == 0) { return getchar(); } /* SYS_GETC; 65535 at EOF */
    c = bios(0x0127, 0, 0);                  /* FGETB: A | carry<<8 */
    while (c & 256) {                        /* carry = end of THIS file */
        if (gnf == 0) { return 65535; }      /* single file -> done */
        if (gidx + 1 >= gnf) { return 65535; }   /* last glob match -> done */
        gidx = gidx + 1;                     /* advance to the next matched file */
        p = gfiles + gidx * 64;              /* pointer var, NOT array+expr as a call arg */
        open_path(p);                        /* a match always exists -> opens */
        c = bios(0x0127, 0, 0);              /* read its first byte (may be EOF too) */
    }
    return c & 255;
}

/* openarg: open the file word at a (space-skipped). 0=none(stdin), 1=opened,
 * 2=not found. A `*`/`?` glob expands to every matching file (read as one
 * concatenated stream); otherwise it is a single named file. */
int openarg(char *a) {
    int i;
    int g;
    fromfile = 0;
    gnf = 0;
    gidx = 0;
    if (*a == 0 || *a == 13) { return 0; }   /* no argument -> stdin */
    g = 0;                                    /* glob if the word holds * or ? */
    i = 0;
    while (a[i] != 0 && a[i] != 13 && a[i] != 32) {
        if (a[i] == '*' || a[i] == '?') { g = 1; }
        i = i + 1;
    }
    if (g) {
        gnf = glob_expand(a, gfiles, 24);
        if (gnf == 0) { return 2; }          /* nothing matched */
        fromfile = 1;
        return open_path(gfiles);            /* open the first match */
    }
    fromfile = 1;
    return open_path(a);                      /* single named file */
}
