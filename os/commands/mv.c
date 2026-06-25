/* mv.c — move/rename a file: MV SRC DST  (Unix `mv`).
 *
 *     RUN /BIN/MV.BIN OLD.TXT NEW.TXT       (and, via PATH, `MV OLD.TXT NEW.TXT`)
 *
 * Implemented as copy-then-delete: P8XFS has no rename primitive, so MV copies
 * SRC to DST (the same streams cp.c uses) and then deletes SRC. This works for a
 * rename in place and for a move across directories; the cost is that the data
 * is rewritten and the old extent is freed lazily (reclaimed by PACK), not an
 * in-place directory-entry rename. MV X X is refused so it can't delete its own
 * only copy.
 *
 * BIOS: FRESOLVE=$0133, FOPEN=$0124, FGETB=$0127, FWOPEN=$012A, FPUTB=$012D,
 * FCLOSE=$0130, FDELETE=$011E.  OS: SYS_GETCWD=$4003.  See cp.c for the SBUF
 * ordering rationale (FRESOLVE DST before FWOPEN). Read buffer at $E000.
 */
char src[80];
char dst[80];

int abspath(char *out, char *a) {             /* arg word -> absolute path; returns chars used */
    int i;
    int j;
    i = 0;
    if (*a != '/') {
        bios(0x4003, out, 0);                 /* SYS_GETCWD */
        while (out[i] != 0) { i = i + 1; }
        if (i > 0 && out[i - 1] != '/') { out[i] = '/'; i = i + 1; }
    }
    j = 0;
    while (a[j] != 0 && a[j] != 13 && a[j] != 32) {
        out[i] = a[j]; i = i + 1; j = j + 1;
    }
    out[i] = 0;
    return j;
}

int streq(char *p, char *q) {
    int i;
    i = 0;
    while (p[i] != 0 && p[i] == q[i]) { i = i + 1; }
    return p[i] == q[i];                       /* both reached NUL together */
}

int main() {
    char *a;
    int n;
    int c;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: MV src dst   move/rename a file");
        return 0;
    }
    n = abspath(src, a);
    if (n == 0) { puts("usage: MV src dst"); return 1; }
    a = a + n;
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13) { puts("usage: MV src dst"); return 1; }
    abspath(dst, a);

    if (streq(src, dst)) { puts("mv: source and dest are the same"); return 1; }

    bios(0x0133, src, 0);                      /* FRESOLVE SRC */
    if (bios(0x0124, 0xE000, 0) & 256) {       /* FOPEN SRC */
        puts("mv: source not found");
        return 1;
    }
    bios(0x0133, dst, 0);                      /* FRESOLVE DST (DIRLBA+FNAME) */
    bios(0x012A, 0, 0);                        /* FWOPEN */
    c = bios(0x0127, 0, 0);                    /* FGETB */
    while ((c & 256) == 0) {
        bios(0x012D, 0, c & 255);              /* FPUTB */
        c = bios(0x0127, 0, 0);
    }
    bios(0x0130, 0, 0);                        /* FCLOSE -> commit DST */

    bios(0x0133, src, 0);                      /* FRESOLVE SRC again, then delete it */
    bios(0x011E, 0, 0);                        /* FDELETE SRC */
    return 0;
}
