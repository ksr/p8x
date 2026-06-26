/* cat.c — print files, or copy stdin to stdout (the canonical filter).
 *
 *     RUN /BIN/CAT.BIN FILE        -> print FILE   (Unix `cat file`)
 *     RUN /BIN/CAT.BIN <FILE       -> print FILE   (stdin redirect)
 *     RUN /BIN/CAT.BIN <IN >OUT    -> copy IN to OUT
 *     RUN /BIN/CAT.BIN | ...       -> as a pipe stage
 *  (and, with implicit RUN + PATH, simply `CAT FILE`).
 *
 * With a filename argument cat opens that file directly; with no argument it
 * reads stdin (SYS_GETC), so shell redirection (`<`) and pipes (`|`) still work
 * unchanged — the two modes are independent, exactly like Unix cat.
 *
 * Opening a named file: the BIOS read stream (FOPEN/FGETB) resolves a name in
 * the BIOS "current directory", which for a fresh program is the root — not the
 * shell's CWD. So we build an ABSOLUTE path (the CWD via SYS_GETCWD, unless the
 * argument is already absolute), FRESOLVE it (always starts at root, so it is
 * CWD-independent), then FOPEN. The 512-byte read buffer is a fixed page-aligned
 * scratch high in the TPA ($FC00), clear of our code/globals at $B000 and the
 * stack at $FEFF (p8cc has no preprocessor, so it is written as a literal).
 *
 * BIOS: FRESOLVE=$0133 (P1=path), FOPEN=$0124 (P1=buffer; C=1 not found),
 * FGETB=$0127 (->A, C=1 at EOF).  OS: SYS_GETCWD=$4003.
 */
char path[80];                               /* absolute path we build for the arg */

int main() {
    char *arg;
    int i;
    int j;
    int c;

    arg = argstr();                          /* the command tail */
    while (*arg == 32) { arg = arg + 1; }    /* skip leading spaces */

    if (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H')) {
        puts("usage: CAT [file]   print file, or filter stdin if no file");
        return 0;
    }

    if (*arg == 0 || *arg == 13) {           /* no file -> filter stdin */
        c = getchar();
        while (c != 65535) { putchar(c); c = getchar(); }
        return 0;
    }

    i = 0;                                    /* build an absolute path in path[] */
    if (*arg != '/') {                        /* relative -> prepend the CWD */
        bios(0x4003, path, 0);                /* SYS_GETCWD -> path */
        while (path[i] != 0) { i = i + 1; }   /* i = end of the CWD string */
        if (i > 0 && path[i - 1] != '/') { path[i] = '/'; i = i + 1; }
    }
    j = 0;                                     /* append the arg word (stop at space/CR) */
    while (arg[j] != 0 && arg[j] != 13 && arg[j] != 32) {
        path[i] = arg[j]; i = i + 1; j = j + 1;
    }
    path[i] = 0;

    bios(0x0133, path, 0);                    /* FRESOLVE: DIRLBA=parent, FNAME=leaf */
    if (bios(0x0124, 0xFC00, 0) & 256) {      /* FOPEN; carry=1 -> not found */
        puts("cat: not found");
        return 1;
    }
    c = bios(0x0127, 0, 0);                    /* FGETB */
    while ((c & 256) == 0) {                   /* carry=1 -> end of file */
        putchar(c & 255);
        c = bios(0x0127, 0, 0);
    }
    return 0;
}
