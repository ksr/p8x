/* man.c — print a manual page: MAN name  ->  the text of /man/NAME.
 *
 *     MAN dir            print the manual page for the DIR command
 *     MAN man            ... man's own page
 *     RUN /BIN/MAN.BIN cat
 *
 * Manual pages are plain-text files in the /man directory, one per command
 * (bare lower-case names, matching the command). man just resolves "/man/" +
 * the requested name and streams the file to stdout — it is `cat` with a fixed
 * directory prefix, so it is CWD-independent (FRESOLVE always starts at root).
 * A missing page prints "no manual entry for NAME" (like Unix man).
 *
 * BIOS: FRESOLVE=$0133 (P1=path), FOPEN=$0124 (P1=buffer; C=1 not found),
 * FGETB=$0127 (->A, C=1 at EOF).  512-byte read buffer at $FC00 (page-aligned,
 * clear of code/globals at $6A00 and the stack at $FEFF).
 */
//#use abi     /* FRESOLVE, FOPEN, FGETB, RDBUF ($FC00); no SYS_GETCWD — man is CWD-independent */

char path[80];                               /* "/man/" + the requested name */

/* main — resolve the argument to /man/NAME and stream that file to stdout.
 * Returns 0 on success (or after printing usage), 1 if the page is missing.
 * bios() returns the BIOS result with the CPU carry flag folded into bit 8,
 * so "& 256" tests carry: FOPEN sets it when the path is not found and FGETB
 * sets it at end of file.  puts() (usage line) appends its own newline. */
int main() {
    char *arg;
    char *p;
    int i;
    int j;
    int c;

    arg = argstr();                          /* the command tail */
    while (*arg == 32) { arg = arg + 1; }    /* skip leading spaces */

    if (*arg == 0 || *arg == 13 ||
        (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H'))) {
        puts("usage: MAN name   show the manual page for a command");
        return 0;
    }

    path[0] = '/';                            /* build "/man/NAME" */
    path[1] = 'm';
    path[2] = 'a';
    path[3] = 'n';
    path[4] = '/';
    i = 5;
    j = 0;
    while (arg[j] != 0 && arg[j] != 13 && arg[j] != 32) {
        path[i] = arg[j]; i = i + 1; j = j + 1;
    }
    path[i] = 0;                              /* NUL-terminate the built path */

    /* FRESOLVE walks "path" from root, leaving DIRLBA=parent dir and FNAME=leaf
     * for the following FOPEN.  FOPEN reads into RDBUF (the $FC00 page buffer). */
    bios(FRESOLVE, path, 0);                    /* FRESOLVE: DIRLBA=parent, FNAME=leaf */
    if (bios(FOPEN, RDBUF, 0) & 256) {      /* FOPEN; carry=1 -> not found */
        p = "no manual entry for ";
        i = 0;
        while (p[i] != 0) { putchar(p[i]); i = i + 1; }
        i = 5;                                /* the name part of "/man/NAME" */
        while (path[i] != 0) { putchar(path[i]); i = i + 1; }
        putchar(10);
        return 1;
    }
    c = bios(FGETB, 0, 0);                    /* FGETB */
    while ((c & 256) == 0) {                   /* carry=1 -> end of file */
        putchar(c & 255);
        c = bios(FGETB, 0, 0);
    }
    return 0;
}
