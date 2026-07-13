/* cp.c — copy files: CP [-r] src dst  (Unix `cp`, plus `cp -r` for a subtree).
 *
 *     CP OLD.TXT NEW.TXT            copy one file
 *     CP -r SRC DST                 copy a directory tree recursively
 *     CP -r /d1/SRC /SRC            ... across the mount (drive 1 -> drive 0)
 *     CP *.ASM /BAK                 glob source -> copy each match into a dir
 *
 * A `*`/`?` in the source is a glob: it is expanded (lib_globx) and every match
 * is copied INTO the destination, which must be an existing directory (each copy
 * lands at <dst>/<basename>). With -r a matched subdirectory is copied as a tree.
 *
 * A single file is read through the BIOS read stream (FOPEN/FGETB, buffer $FC00)
 * and written through the write stream (FWOPEN/FPUTB/FCLOSE); the two use
 * independent buffers so the byte loop interleaves them. Both paths are made
 * absolute (via abspath) and resolved with FRESOLVE, which applies the /d1 mount
 * redirect — so a cross-mount copy needs no special handling: each stream keeps
 * its own drive (ROSDRV/WOSDRV).
 *
 * `-r`: copy_tree() makes the destination directory (SYS_MKDIR), then walks the
 * source directory ONE LEVEL, collecting its entries into local arrays FIRST
 * (the BIOS FNEXT cursor is global state, so we cannot recurse while iterating),
 * then processes them — files via copy_file(), subdirectories by recursing.
 * Params are copied to locals on entry so the recursion preserves each level's
 * paths; the child-path scratch (JSRC/JDST) is global and rebuilt per entry.
 *
 * BIOS: FRESOLVE=$0133, FOPEN=$0124, FGETB=$0127, FWOPEN=$012A, FPUTB=$012D,
 * FCLOSE=$0130, FOPENDIR=$0139, FNEXT=$013C, FSDIRBUF=$0145.  OS: SYS_MKDIR=$2021.
 * Within the p8cc subset (no ++/--, decls at top, self-recursion only).
 */
char src[80];
char dst[80];
char jsrc[80];                       /* child-path scratch: <dir>/<name> */
char jdst[80];
char patw[80];                       /* the source arg word (may be a glob) */
char gfiles[1536];                   /* glob_expand output: 24 slots x 64 */

//#use apath   /* abspath(out, arg): next path word -> absolute in out */
//#use dirent    /* de_read/de_isdir/de_isdot + de[] : current entry via syscall */
//#use globx     /* glob_expand(pat, out, maxn): expand a glob into a path list */

/* scopy: copy NUL-terminated s into d; return the length. */
int scopy(char *d, char *s) {
    int i;
    i = 0;
    while (s[i] != 0) { d[i] = s[i]; i = i + 1; }
    d[i] = 0;
    return i;
}

/* joinp: out = dir + "/" + name  (name is NUL-terminated). */
int joinp(char *out, char *dir, char *name) {
    int i;
    int j;
    i = scopy(out, dir);
    if (i == 0 || out[i - 1] != '/') { out[i] = '/'; i = i + 1; }
    j = 0;
    while (name[j] != 0) { out[i] = name[j]; i = i + 1; j = j + 1; }
    out[i] = 0;
    return i;
}

/* copy_file: copy the file at absolute path s to absolute path d.
 * Returns 1 if the source was not found, else 0. */
int copy_file(char *s, char *d) {
    int c;
    bios(0x0133, s, 0);                       /* FRESOLVE SRC (applies /d1) */
    if (bios(0x0124, 0xFC00, 0) & 256) { return 1; }   /* FOPEN; C=1 -> not found */
    bios(0x0133, d, 0);                       /* FRESOLVE DST (DIRLBA + FNAME) */
    bios(0x012A, 0, 0);                       /* FWOPEN (zeroes SBUF last) */
    c = bios(0x0127, 0, 0);                   /* FGETB */
    while ((c & 256) == 0) {
        bios(0x012D, 0, c & 255);             /* FPUTB */
        c = bios(0x0127, 0, 0);
    }
    bios(0x0130, 0, 0);                       /* FCLOSE -> commit DST */
    return 0;
}

/* isdir: 1 if the absolute path p names a directory (FOPENDIR succeeds). */
int isdir(char *p) {
    if (bios(0x0139, p, 0) & 256) { return 0; }   /* FOPENDIR; C=1 -> not a dir */
    return 1;
}

/* copy_tree: recursively copy the directory at absolute path sp0 to dp0.
 * sp0 must be a directory; dp0 is created if needed. */
int copy_tree(char *sp0, char *dp0) {
    char sp[80];                              /* local copies: recursion-safe */
    char dp[80];
    char names[288];                          /* up to 24 entries x 12 bytes */
    int  isd[24];                             /* 1 = subdirectory */
    int  n;
    int  i;
    int  k;
    int  r;
    scopy(sp, sp0);
    scopy(dp, dp0);
    bios(0x2021, dp, 0);                      /* SYS_MKDIR dst (idempotent) */

    n = 0;                                     /* collect this level's entries */
    bios(0x0139, sp, 0);                       /* FOPENDIR src */
    bios(0x0145, 0, 0xE0);                     /* FSDIRBUF: iterate on page $E000.
                                                * Above cp's code/globals (adding
                                                * //#use globx grew the binary past
                                                * the old $A000 page) and clear of
                                                * the $FC00 read buffer / $FE00
                                                * stack. glob_expand's $FA00 page
                                                * runs earlier, so no overlap. */
    r = bios(0x013C, 0, 0);                    /* FNEXT */
    while ((r & 256) == 0) {
        de_read();
        if (de_isdot() == 0 && n < 24) {
            k = 0;                             /* trim de[] name into names[n*12] */
            while (k < 12 && (de[k] & 255) != 32) {
                names[n * 12 + k] = de[k];
                k = k + 1;
            }
            while (k < 12) { names[n * 12 + k] = 0; k = k + 1; }
            isd[n] = de_isdir();
            n = n + 1;
        }
        r = bios(0x013C, 0, 0);
    }

    i = 0;                                     /* now process (safe to recurse) */
    while (i < n) {
        joinp(jsrc, sp, names + i * 12);       /* <sp>/<name> ; global scratch */
        joinp(jdst, dp, names + i * 12);
        if (isd[i]) { copy_tree(jsrc, jdst); } /* recurse (copies args to locals) */
        else { copy_file(jsrc, jdst); }
        i = i + 1;
    }
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
    int rec;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H')) {
        puts("usage: CP [-r] src dst   copy a file/glob, or -r a directory tree");
        return 0;
    }
    rec = 0;
    if (*a == '-' && (*(a + 1) == 'r' || *(a + 1) == 'R')) {
        rec = 1;
        a = a + 2;
        while (*a == 32) { a = a + 1; }
    }
    if (*a == 0 || *a == 13) { puts("usage: CP [-r] src dst"); return 1; }

    g = 0;                                      /* copy the SRC word; note glob */
    i = 0;
    while (a[i] != 0 && a[i] != 13 && a[i] != 32) {
        if (a[i] == '*' || a[i] == '?') { g = 1; }
        patw[i] = a[i]; i = i + 1;
    }
    patw[i] = 0;
    a = a + i;
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13) { puts("usage: CP [-r] src dst"); return 1; }
    abspath(dst, a);                           /* DST word */

    if (g == 0) {                               /* single named source */
        abspath(src, patw);
        if (rec && isdir(src)) { copy_tree(src, dst); return 0; }
        if (copy_file(src, dst)) { puts("cp: source not found"); return 1; }
        return 0;
    }

    if (isdir(dst) == 0) {                       /* glob -> dst must be a dir */
        puts("cp: target is not a directory");
        return 1;
    }
    nm = glob_expand(patw, gfiles, 24);
    if (nm == 0) { puts("cp: no match"); return 1; }
    i = 0;
    while (i < nm) {
        m = gfiles + i * 64;                    /* one match (dir prefix + name) */
        abspath(src, m);
        b = 0;                                  /* basename = after the last '/' */
        j = 0;
        while (m[j] != 0) { if (m[j] == '/') { b = j + 1; } j = j + 1; }
        joinp(jdst, dst, m + b);                /* <dst>/<basename> */
        if (rec && isdir(src)) { copy_tree(src, jdst); }
        else { copy_file(src, jdst); }
        i = i + 1;
    }
    return 0;
}
