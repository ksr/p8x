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
//#use abi     /* FRESOLVE, FOPEN, FGETB, RDBUF ($FC00), PUTS; no SYS_GETCWD — man is CWD-independent */
//#use err     /* eputs(): errors -> console, never into a redirect/pipe */

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
    /* path[80] holds "/man/" (5) + name + NUL, so the name caps at 74 chars;
     * stop at i==79 to leave room for the terminator. Real page names are short
     * command names, so the cap only bites input that no page could match. */
    while (arg[j] != 0 && arg[j] != 13 && arg[j] != 32 && i < 79) {
        path[i] = arg[j]; i = i + 1; j = j + 1;
    }
    path[i] = 0;                              /* NUL-terminate the built path */

    /* FRESOLVE walks "path" from root, leaving DIRLBA=parent dir and FNAME=leaf
     * for the following FOPEN.  FOPEN reads into RDBUF (the $FC00 page buffer). */
    bios(FRESOLVE, path, 0);                    /* FRESOLVE: DIRLBA=parent, FNAME=leaf */
    if (bios(FOPEN, RDBUF, 0) & 256) {      /* FOPEN; carry=1 -> not found */
        /* Failure path: this diagnostic must never enter a redirect or a pipe
         * (`man nope >notes` would write it into notes, `man nope | wc` would
         * count it as data), so both halves go straight to the console via PUTS
         * — eputs() finishes the second half with the newline on the same sink. */
        p = "no manual entry for ";
        bios(PUTS, p, 0);                     /* first half, no newline yet */
        p = path + 5;                         /* the name part of "/man/NAME" */
        eputs(p);                             /* name + its trailing newline */
        return 1;
    }
    c = bios(FGETB, 0, 0);                    /* FGETB */
    while ((c & 256) == 0) {                   /* carry=1 -> end of file */
        putchar(c & 255);
        c = bios(FGETB, 0, 0);
    }
    return 0;
}
