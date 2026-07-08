/* cat.c — print files, or copy stdin to stdout (the canonical filter).
 *
 *     RUN /BIN/CAT.BIN FILE        -> print FILE   (Unix `cat file`)
 *     CAT *.ASM                    -> concatenate every matching file (glob)
 *     CAT *.ASM >ALL.TXT           -> ... into a file (shell redirect)
 *     RUN /BIN/CAT.BIN <FILE       -> print FILE   (stdin redirect)
 *     RUN /BIN/CAT.BIN | ...       -> as a pipe stage
 *  (and, with implicit RUN + PATH, simply `CAT FILE`).
 *
 * With a filename argument cat opens that file directly; if the argument is a
 * glob (`*`/`?` in the last component) it concatenates every matching FILE in
 * that directory (via lib_globx's glob_expand); with no argument it reads stdin
 * (SYS_GETC), so `<` and `|` still work — the modes are independent like Unix.
 *
 * Opening a named file: the BIOS read stream (FOPEN/FGETB) resolves a name in
 * the BIOS "current directory", which for a fresh program is the root — not the
 * shell's CWD. So we build an ABSOLUTE path (the CWD via SYS_GETCWD, unless the
 * argument is already absolute), FRESOLVE it (always starts at root, so it is
 * CWD-independent), then FOPEN. The 512-byte read buffer is a fixed page-aligned
 * scratch high in the TPA ($FC00), clear of our code/globals at $7A00 and the
 * stack at $FEFF (p8cc has no preprocessor, so it is written as a literal).
 *
 * BIOS: FRESOLVE=$0133 (P1=path), FOPEN=$0124 (P1=buffer; C=1 not found),
 * FGETB=$0127 (->A, C=1 at EOF).  OS: SYS_GETCWD=$4003.
 */
//#use glob    /* gmatch() — required by glob_expand below */
//#use globx   /* glob_expand(pat, out, maxn): expand a glob into a path list */

char path[80];                               /* absolute path we build per file */
char gbuf[1536];                             /* glob_expand output: 24 slots x 64 */

/* catpath: stream one file (arg may be relative -> CWD, or absolute) to stdout.
 * Returns 1 if the file was not found, else 0. */
int catpath(char *arg) {
    int i;
    int j;
    int c;
    i = 0;                                    /* build an absolute path in path[] */
    if (*arg != '/') {                        /* relative -> prepend the CWD */
        bios(0x4003, path, 0);                /* SYS_GETCWD -> path */
        while (path[i] != 0) { i = i + 1; }
        if (i > 0 && path[i - 1] != '/') { path[i] = '/'; i = i + 1; }
    }
    j = 0;                                     /* append the arg word (stop at space/CR) */
    while (arg[j] != 0 && arg[j] != 13 && arg[j] != 32) {
        path[i] = arg[j]; i = i + 1; j = j + 1;
    }
    path[i] = 0;
    bios(0x0133, path, 0);                    /* FRESOLVE: DIRLBA=parent, FNAME=leaf */
    if (bios(0x0124, 0xFC00, 0) & 256) { return 1; }   /* FOPEN; carry=1 -> not found */
    c = bios(0x0127, 0, 0);                    /* FGETB */
    while ((c & 256) == 0) {                   /* carry=1 -> end of file */
        putchar(c & 255);
        c = bios(0x0127, 0, 0);
    }
    return 0;
}

int main() {
    char *arg;
    char *p;
    int i;
    int c;
    int g;
    int n;

    arg = argstr();                          /* the command tail */
    while (*arg == 32) { arg = arg + 1; }    /* skip leading spaces */

    if (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H')) {
        puts("usage: CAT [file|glob]   print file(s), or filter stdin if none");
        return 0;
    }

    if (*arg == 0 || *arg == 13) {           /* no file -> filter stdin */
        c = getchar();
        while (c != 65535) { putchar(c); c = getchar(); }
        return 0;
    }

    g = 0;                                    /* glob if the arg has '*' or '?' */
    i = 0;
    while (arg[i] != 0 && arg[i] != 13 && arg[i] != 32) {
        if (arg[i] == '*' || arg[i] == '?') { g = 1; }
        i = i + 1;
    }

    if (g) {                                  /* concatenate every match */
        n = glob_expand(arg, gbuf, 24);
        p = gbuf;
        i = 0;
        while (i < n) {
            catpath(p);                       /* a match always exists -> ignore 1 */
            p = p + 64;
            i = i + 1;
        }
        return 0;
    }

    if (catpath(arg)) { puts("cat: not found"); return 1; }   /* single file */
    return 0;
}
