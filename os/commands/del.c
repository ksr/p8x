/* del.c — remove file(s). Moved OUT of the shell into /bin (2026-09-09): the
 * OS shell used to carry DEL as a built-in, but it is a self-contained
 * filesystem op that touches no shell state, so it belongs alongside the other
 * external file commands (touch, cp, mv) and frees room in the resident OS.
 *
 *     DEL NAME              tombstone NAME (Unix `rm`, minus recursion/flags)
 *     DEL A.TXT B.TXT       several at once
 *     DEL /d1/JUNK.DAT      absolute / cross-mount paths work
 *
 * Each name is made absolute (CWD-relative via abspath — /bin programs must,
 * since FRESOLVE starts at the root, not the CWD) and then tombstoned with the
 * FDELETE BIOS call, which marks the directory entry deleted and persists the
 * sector. Files only: a directory is removed with RMDIR. No globbing yet.
 *
 * BIOS: FRESOLVE=$0133 (path -> DIRLBA + FNAME), FDELETE=$011E (tombstone FNAME;
 * C=1 = not found).
 */
char path[80];

//#use apath   /* abspath(out, arg): next path word -> absolute in out */
//#use abi     /* named BIOS/OS addresses: FRESOLVE, FDELETE, ... */

/* main: remove each whitespace-separated name in the command tail. `a` walks
 * the raw argument string; `path` holds the absolutized name for each word. */
int main() {
    char *a;
    int n;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: DEL name [name...]   remove file(s)");
        return 0;
    }

    while (*a != 0 && *a != 13) {              /* each whitespace-separated name */
        n = abspath(path, a);                  /* CWD-relative -> absolute */
        if (n == 0) { return 0; }
        a = a + n;
        while (*a == 32) { a = a + 1; }        /* skip spaces before the next name */
        bios(FRESOLVE, path, 0);               /* path -> DIRLBA + FNAME */
        if (bios(FDELETE, 0, 0) & 256) {       /* tombstone; C=1 -> not found */
            puts("?No such file");
        }
    }
    return 0;
}
