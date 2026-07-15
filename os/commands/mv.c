/* mv.c — move/rename a file: MV SRC DST  (Unix `mv`).
 *
 *     RUN /BIN/MV.BIN OLD.TXT NEW.TXT       (and, via PATH, `MV OLD.TXT NEW.TXT`)
 *     MV *.TMP TRASH                        glob source -> move each into a dir
 *
 * Implemented as copy-then-delete: P8XFS has no rename primitive, so MV copies
 * SRC to DST (the same streams cp.c uses) and then deletes SRC. This works for a
 * rename in place and for a move across directories; the cost is that the data
 * is rewritten and the old extent is freed lazily (reclaimed by PACK), not an
 * in-place directory-entry rename. MV X X is refused so it can't delete its own
 * only copy.
 *
 * A `*`/`?` in the source is a glob: every match is moved INTO the destination,
 * which must be an existing directory (each lands at <dst>/<basename>).
 *
 * BIOS: FRESOLVE=$0133, FOPEN=$0124, FGETB=$0127, FWOPEN=$012A, FPUTB=$012D,
 * FCLOSE=$0130, FDELETE=$011E, FOPENDIR=$0139.  OS: SYS_GETCWD=$2003.  See cp.c
 * for the SBUF ordering rationale (FRESOLVE DST before FWOPEN). Read buf $FC00.
 */
char src[80];
char dst[80];
char jdst[80];                       /* <dst>/<basename> for a glob move */
char patw[80];                       /* the source arg word (may be a glob) */
char gfiles[1536];                   /* glob_expand output: 24 slots x 64 bytes each
                                        (must match the maxn=24 / stride-64 used below) */

//#use apath
//#use streq
//#use globx     /* glob_expand(pat, out, maxn): expand a glob into a path list */
//#use abi     /* named BIOS/OS addresses: FOPEN, FGETB, SYS_GETCWD, RDBUF, ... */

/* joinp: out = dir + "/" + name (name NUL-terminated). */
int joinp(char *out, char *dir, char *name) {
    int i;
    int j;
    i = 0;
    while (dir[i] != 0) { out[i] = dir[i]; i = i + 1; }
    if (i == 0 || out[i - 1] != '/') { out[i] = '/'; i = i + 1; }
    j = 0;
    while (name[j] != 0) { out[i] = name[j]; i = i + 1; j = j + 1; }
    out[i] = 0;
    return i;
}

/* move_one: copy absolute path s to absolute path d, then delete s.
 * Returns 1 if the source was not found, else 0. */
int move_one(char *s, char *d) {
    int c;
    /* bios() returns the P8X flags in the high byte, so bit 8 (&256) is the carry
     * flag. FRESOLVE loads DIRLBA+FNAME from a path; it must be redone before each
     * FOPEN/FWOPEN/FDELETE because those consume that resolved location. */
    bios(FRESOLVE, s, 0);                        /* FRESOLVE SRC */
    if (bios(FOPEN, RDBUF, 0) & 256) { return 1; }   /* FOPEN into RDBUF; C=1 -> not found */
    bios(FRESOLVE, d, 0);                        /* FRESOLVE DST (DIRLBA + FNAME) */
    bios(FWOPEN, 0, 0);                        /* FWOPEN: create/truncate DST for writing */
    /* Byte-copy loop: FGETB returns C=1 (bit 8 set) at EOF; low byte is the data. */
    c = bios(FGETB, 0, 0);                    /* FGETB */
    while ((c & 256) == 0) {
        bios(FPUTB, 0, c & 255);              /* FPUTB low byte to DST */
        c = bios(FGETB, 0, 0);
    }
    bios(FCLOSE, 0, 0);                        /* FCLOSE -> commit DST */
    bios(FRESOLVE, s, 0);                        /* FRESOLVE SRC again, delete it */
    bios(FDELETE, 0, 0);                        /* FDELETE SRC */
    return 0;
}

int main() {
    char *a;
    char *m;
    int i;
    int j;
    int b;
    int g;
    int nm;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: MV src dst   move/rename a file (or a glob into a dir)");
        return 0;
    }

    /* Parse SRC: copy the first whitespace/CR-terminated word into patw[], and
     * set g=1 if it contains a glob metachar so we branch to the multi-move path. */
    g = 0;                                     /* copy the SRC word; note glob */
    i = 0;
    while (a[i] != 0 && a[i] != 13 && a[i] != 32) {
        if (a[i] == '*' || a[i] == '?') { g = 1; }
        patw[i] = a[i]; i = i + 1;
    }
    patw[i] = 0;
    if (i == 0) { puts("usage: MV src dst"); return 1; }
    a = a + i;
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13) { puts("usage: MV src dst"); return 1; }
    abspath(dst, a);                           /* DST word */

    if (g == 0) {                              /* single named source */
        abspath(src, patw);
        if (streq(src, dst)) { puts("mv: source and dest are the same"); return 1; }
        if (move_one(src, dst)) { puts("mv: source not found"); return 1; }
        return 0;
    }

    if (bios(FOPENDIR, dst, 0) & 256) {          /* glob -> dst must be a dir */
        puts("mv: target is not a directory");
        return 1;
    }
    nm = glob_expand(patw, gfiles, 24);
    if (nm == 0) { puts("mv: no match"); return 1; }
    i = 0;
    while (i < nm) {
        m = gfiles + i * 64;                    /* one match (dir prefix + name) */
        abspath(src, m);
        b = 0;                                  /* basename = after the last '/' */
        j = 0;                                  /* scan to end, tracking last-slash+1 */
        while (m[j] != 0) { if (m[j] == '/') { b = j + 1; } j = j + 1; }
        joinp(jdst, dst, m + b);                /* <dst>/<basename> */
        move_one(src, jdst);
        i = i + 1;
    }
    return 0;
}
