/* touch.c — create empty file(s) if they don't already exist (Unix `touch`,
 * minus the mtime bump — P8XFS has no timestamps yet; see BACKLOG DS1302 RTC).
 *
 *     TOUCH NAME              create NAME as an empty file if it is missing
 *     TOUCH A.TXT B.TXT C     several at once
 *     TOUCH /d1/NEW.TXT       absolute / cross-mount paths work
 *
 * Each name is made absolute (CWD-relative via abspath) and resolved; if the
 * file already exists it is left completely untouched (NOT truncated — that is
 * the important difference from a plain create), otherwise an empty file is
 * created with the write stream (FWOPEN immediately FCLOSEd, zero bytes).
 *
 * No globbing: like Unix `touch`, a pattern would only ever match files that
 * already exist (a no-op), so a literal name list is all that is useful for the
 * create behavior.
 *
 * BIOS: FRESOLVE=$0133, FOPEN=$0124 (C=1 not found), FWOPEN=$012A, FCLOSE=$0130.
 * OS: SYS_GETCWD=$2003 (via abspath). Read buffer at $FC00.
 */
char path[80];

//#use apath   /* abspath(out, arg): next path word -> absolute in out */
//#use abi     /* named BIOS/OS addresses: FOPEN, FGETB, SYS_GETCWD, RDBUF, ... */

/* exists: 1 if the file at absolute path p is present, else 0.
 * FRESOLVE parses p into the DIRLBA + FNAME that FOPEN then consults; FOPEN
 * returns the carry flag in bit 8 of its result, so `& 256` tests C: C=1 means
 * "not found" (return 0). Clobbers P1/P2 like all file syscalls. */
int exists(char *p) {
    bios(FRESOLVE, p, 0);                        /* FRESOLVE */
    if (bios(FOPEN, RDBUF, 0) & 256) { return 0; }   /* FOPEN; C=1 -> not found */
    return 1;
}

/* main: parse the whitespace-separated name list from the command tail and
 * create each missing file. Returns 0 always (touch reports no per-file status).
 * `a` walks the raw argument string; `path` (the 80-byte global) holds the
 * absolutized name for the current word. */
int main() {
    char *a;
    int n;

    /* argstr() gives the full tail after the command word; skip any leading
     * spaces (32) so we can peek at the first real character. */
    a = argstr();
    while (*a == 32) { a = a + 1; }
    /* No args, bare CR (13, end of line), or a -h/-H flag -> print usage. */
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: TOUCH name [name...]   create empty file(s) if missing");
        return 0;
    }

    while (*a != 0 && *a != 13) {              /* each whitespace-separated name */
        /* abspath consumes one path word from a, writes its CWD-absolute form
         * into path, and returns the number of chars consumed; 0 = no word
         * left (nothing more to do, so we stop). */
        n = abspath(path, a);
        if (n == 0) { return 0; }
        a = a + n;                             /* advance past the consumed word */
        while (*a == 32) { a = a + 1; }        /* skip spaces before next name */
        if (exists(path) == 0) {               /* missing -> create empty */
            bios(FRESOLVE, path, 0);             /* FRESOLVE (DIRLBA + FNAME) */
            bios(FWOPEN, 0, 0);                /* FWOPEN */
            bios(FCLOSE, 0, 0);                /* FCLOSE -> zero-byte file */
        }
    }
    return 0;
}
