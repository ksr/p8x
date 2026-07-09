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
 * OS: SYS_GETCWD=$4003 (via abspath). Read buffer at $FC00.
 */
char path[80];

//#use abspath   /* abspath(out, arg): next path word -> absolute in out */

/* exists: 1 if the file at absolute path p is present, else 0. */
int exists(char *p) {
    bios(0x0133, p, 0);                        /* FRESOLVE */
    if (bios(0x0124, 0xFC00, 0) & 256) { return 0; }   /* FOPEN; C=1 -> not found */
    return 1;
}

int main() {
    char *a;
    int n;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: TOUCH name [name...]   create empty file(s) if missing");
        return 0;
    }

    while (*a != 0 && *a != 13) {              /* each whitespace-separated name */
        n = abspath(path, a);
        if (n == 0) { return 0; }
        a = a + n;
        while (*a == 32) { a = a + 1; }
        if (exists(path) == 0) {               /* missing -> create empty */
            bios(0x0133, path, 0);             /* FRESOLVE (DIRLBA + FNAME) */
            bios(0x012A, 0, 0);                /* FWOPEN */
            bios(0x0130, 0, 0);                /* FCLOSE -> zero-byte file */
        }
    }
    return 0;
}
