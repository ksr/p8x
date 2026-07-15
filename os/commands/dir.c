/* dir.c — the OS DIR command written as a C program for the P8X.
 *
 *     DIR [-R] [-S] [path | glob]
 *
 * Lists a directory: the path argument (via argstr() -> P2), or — with no
 * argument — the current working directory (OS syscall SYS_OPENCWD, no peeking
 * into OS internals). A loadable /BIN/DIR.BIN program.
 *
 *   DIR                 list the CWD, sorted by name
 *   DIR /BIN            list a directory by path
 *   DIR *.ASM           list CWD entries matching a glob (* and ?)
 *   DIR /BIN/*.BIN      glob within another directory
 *   DIR -R              recurse the whole subtree (two-space indent per level)
 *   DIR -S              sort by file size, largest first
 *   DIR -R -S *.C       recurse, size-sorted, printing only entries matching glob
 *
 * SORT: entries are always sorted WITHIN each directory before printing (and,
 * with -R, at every level independently). Default order is by name, raw ASCII
 * (so uppercase A-Z sort before lowercase a-z). With -S the key is byte size,
 * LARGEST first (Unix `ls -S`); ties break by name ascending. Directories carry
 * no displayed size, so under -S they count as size 0 and sort after all files.
 *
 * GLOB: if the path's last component contains '*' or '?', it is a pattern; the
 * part before the last '/' (or the CWD) is the directory to scan, and only
 * entries whose name matches the pattern (case-insensitive, via lib_glob's
 * gmatch) are printed. With -R the filter applies at every level while still
 * descending into all subdirectories.
 *
 * A directory's entries are buffered (name/size/dir-flag/LBA), sorted by an
 * index array, then streamed to stdout, so output is still redirectable and
 * pipeable. The buffers are a single global set reused at every recursion level:
 * a level is fully collected, sorted, printed, and its child LBAs copied into a
 * small per-frame array BEFORE descending, so a child's collect() may reuse the
 * globals freely. Directory iteration (FNEXT) runs on our own page (FSDIRBUF
 * $0145, page $FA00) so a write stream/pipe keeps the BIOS sector buffer SBUF to
 * itself.
 *
 * Each line is a right-justified byte size, two spaces, then the name (a '/'
 * suffix marks a directory). Directories have no byte length, so their size
 * column is left blank. The size is 24-bit (de[13/14] + de[17] via SYS_DIRENTRY):
 * p8cc's int is 16-bit, so the column is printed with a byte-wise divmod10
 * (dm10/putsize24) and sorted with an explicit 24-bit compare (before()).
 *
 * BIOS: FOPENDIR=$0139 (P1=path), FOPENDIRAT=$0142 (A=low,LBA1=$7048 high),
 * FNEXT=$013C (-> FNAME $704A 12 space-padded, FFLAG $7070 file $01/dir $02,
 * start LBA byte0 $7047/byte1 $7048, FLEN $7058 lo/$7059 hi; C=1 at end),
 * FSDIRBUF=$0145.
 * OS: SYS_OPENCWD=$2012 (begin iterating the CWD, full 16-bit LBA).
 */
//#use glob     /* gmatch(pat, name): case-insensitive * ? matcher */
//#use dirent   /* de_read/de_isdir/de_len/de_lba/de_opendir: entry via syscall */
//#use apath    /* abspath(out, a): CWD-prefix a relative path (FRESOLVE starts at root) */
//#use abi     /* named BIOS/OS addresses: FOPEN, FGETB, SYS_GETCWD, RDBUF, ... */

char nbuf[16];                               /* current entry name, NUL-terminated */
char gpat[16];                               /* glob pattern, or empty = no filter */

/* Per-directory entry buffers, filled by collect() and reused at every recursion
 * level (a level is printed before its children overwrite them). Cap 64 = a
 * fresh directory extent (4 sectors * 16 entries). */
char enam[768];                              /* 64 names, 12 space-padded bytes each */
int  elen[64];                               /* byte length low 16 (0 for dirs) */
char elen2[64];                              /* byte length bits 16..23 (24-bit size) */
char num24[3];                               /* scratch little-endian 24-bit for printing */
char dg[8];                                   /* digit buffer for putsize24 */
char eisd[64];                               /* 1 = directory (char: house rule — */
int  elba[64];                               /* start LBA (for -R descent); 16-bit */
char eidx[64];                               /* sorted print order (indices 0..63; a */
                                             /* char, not int: p8cc int arrays as a */
                                             /* sort permutation misbehave — see the */
                                             /* os/commands/README.md p8cc notes) */
int  ecnt;                                   /* entries collected this level */
int  szmode;                                 /* 1 = -S size sort, 0 = name sort */

/* dm10: divide the 24-bit little-endian num24[] by 10 in place, return the
 * remainder (0..9). p8cc's int is 16-bit, so a >64 KB size can't live in one int
 * — long-divide it a byte at a time. cur = rem*256 + byte fits (rem<10). */
int dm10() {
    int rem;
    int i;
    int cur;
    int n;
    rem = 0;
    i = 2;
    n = 3;                                         /* count down (p8cc >= 0 is
                                                     unsigned-broken for i<0) */
    while (n != 0) {
        cur = rem * 256 + (num24[i] & 255);
        num24[i] = cur / 10;
        rem = cur - (cur / 10) * 10;
        i = i - 1;
        n = n - 1;
    }
    return rem;
}

/* putsize24: a 6-wide size column, right-justified, from a 24-bit size (lo = low
 * 16 bits, hi = bits 16..23). Directories (isdir) get six blanks (no byte length). */
int nz24() {                                      /* num24 != 0 ? (avoid || in a loop) */
    if (num24[0] != 0) { return 1; }
    if (num24[1] != 0) { return 1; }
    if (num24[2] != 0) { return 1; }
    return 0;
}

int putsize24(int isdir, int lo, int hi) {
    int nd;
    int i;
    if (isdir) {
        i = 0;
        while (i < 6) { putchar(32); i = i + 1; }
        return 0;
    }
    num24[0] = lo & 255;
    num24[1] = (lo / 256) & 255;                  /* p8cc / is unsigned */
    num24[2] = hi & 255;
    nd = 0;
    dg[nd] = 48 + dm10();                          /* at least one digit (handles 0) */
    nd = nd + 1;
    while (nz24()) {
        dg[nd] = 48 + dm10();
        nd = nd + 1;
    }
    i = nd;
    while (i < 6) { putchar(32); i = i + 1; }      /* pad to width 6 */
    while (nd != 0) { nd = nd - 1; putchar(dg[nd]); }  /* LS-first -> print reversed */
    return 0;
}

/* nameat: nbuf <- enam[m] (12 space-padded bytes), trailing pad trimmed. */
int nameat(int m) {
    int i;
    int c;
    int base;
    base = m * 12;
    i = 0;
    c = enam[base] & 255;
    while (i < 12 && c != 32) {
        nbuf[i] = c;
        i = i + 1;
        c = enam[base + i] & 255;
    }
    nbuf[i] = 0;
    return i;
}

/* namecmp: compare the 12-byte padded names of entries a and b, raw ASCII.
 * Returns 1 if a<b, 2 if a>b, 0 if equal. (No signed subtraction: p8cc's < is
 * unsigned, so `diff < 0` would never be true — compare the bytes directly.) */
int namecmp(int a, int b) {
    int i;
    int ca;
    int cb;
    int pa;
    int pb;
    pa = a * 12;
    pb = b * 12;
    i = 0;
    while (i < 12) {
        ca = enam[pa + i] & 255;
        cb = enam[pb + i] & 255;
        if (ca < cb) { return 1; }
        if (ca > cb) { return 2; }
        i = i + 1;
    }
    return 0;
}

/* before: does entry a sort strictly before entry b? Size mode: larger key
 * first, name ascending on a tie. Name mode: name ascending. */
int before(int a, int b) {
    int ha;
    int hb;
    int la;
    int lb;
    if (szmode) {
        ha = 0; if (eisd[a] == 0) { ha = elen2[a] & 255; }   /* 24-bit key: dir -> 0 */
        hb = 0; if (eisd[b] == 0) { hb = elen2[b] & 255; }
        if (ha > hb) { return 1; }                /* larger first */
        if (ha < hb) { return 0; }
        la = 0; if (eisd[a] == 0) { la = elen[a]; }          /* high tied -> low 16 */
        lb = 0; if (eisd[b] == 0) { lb = elen[b]; }
        if (la > lb) { return 1; }
        if (la < lb) { return 0; }
        return namecmp(a, b) == 1;                /* size tied -> name ascending */
    }
    return namecmp(a, b) == 1;
}

/* collect: iterate the ALREADY-open directory (caller did FOPENDIR/FOPENDIRAT +
 * FSDIRBUF), snapshot every non-dot entry into the global buffers, and build a
 * sorted index (selection sort) in eidx[]. Leaves ecnt = count. */
int collect() {
    int r;
    int k;
    int base;
    int i;
    int j;
    int m;
    int t;

    k = 0;
    r = bios(FNEXT, 0, 0);                  /* FNEXT */
    while ((r & 256) == 0) {                  /* bit 8 = carry = end of directory */
        de_read();                            /* snapshot the entry (SYS_DIRENTRY) */
        if (de_isdot() == 0) {                /* skip '.' and '..' */
            if (k < 64) {                     /* cap 64: extra entries silently dropped */
                base = k * 12;
                i = 0;
                while (i < 12) { enam[base + i] = de[i]; i = i + 1; }
                if (de_isdir()) { eisd[k] = 1; elen[k] = 0; elen2[k] = 0; }
                /* file: low 16 bits from de_len(), bits 16..23 from dir-entry
                 * byte 17 (the third size byte) -> full 24-bit length */
                else { eisd[k] = 0; elen[k] = de_len(); elen2[k] = de[17] & 255; }
                elba[k] = de_lba();
                k = k + 1;
            }
        }
        r = bios(FNEXT, 0, 0);
    }
    ecnt = k;

    i = 0;                                     /* eidx[i] = i */
    while (i < ecnt) { eidx[i] = i; i = i + 1; }
    i = 0;                                     /* selection sort by before() */
    while (i < ecnt) {
        m = i;
        j = i + 1;
        while (j < ecnt) {
            if (before(eidx[j], eidx[m])) { m = j; }
            j = j + 1;
        }
        t = eidx[i]; eidx[i] = eidx[m]; eidx[m] = t;
        i = i + 1;
    }
    return ecnt;
}

/* show: print "<size>  <indent><name>[/]" if nbuf passes the glob filter.
 * The size column aligns first so it lines up regardless of -R indent depth. */
int show(int depth, int isdir, int lo, int hi) {
    int i;
    if (gpat[0] != 0 && gmatch(gpat, nbuf) == 0) { return 0; }   /* filtered out */
    putsize24(isdir, lo, hi);
    putchar(32); putchar(32);                                    /* gap before name */
    i = 0;
    while (i < depth) { putchar(32); putchar(32); i = i + 1; }    /* -R indent */
    i = 0;
    while (nbuf[i] != 0) { putchar(nbuf[i]); i = i + 1; }
    if (isdir) { putchar('/'); }
    putchar(10);
    return 0;
}

/* Recurse the directory whose iteration is ALREADY open (caller did
 * FOPENDIR/FOPENDIRAT + FSDIRBUF). depth = indentation level. Collect + sort the
 * whole level, print it, record child LBAs (in sorted order) into a small local
 * array, then descend — the globals are free to be reused by each child. */
int walk(int depth) {
    int sub[64];            /* child subdirectory start LBAs, sorted order */
    int nsub;
    int i;
    int m;

    collect();                                /* fills globals, sorts eidx[] */
    nsub = 0;
    i = 0;
    while (i < ecnt) {
        m = eidx[i];
        nameat(m);
        show(depth, eisd[m], elen[m], elen2[m]);        /* print (filtered) name + size */
        if (eisd[m]) {                        /* always record subdirs for the pass */
            if (nsub < 64) {
                sub[nsub] = elba[m];
                nsub = nsub + 1;
            }
        }
        i = i + 1;
    }
    /* This level is printed; now descend into each recorded child in order. */
    i = 0;
    while (i < nsub) {
        de_opendir(sub[i]);                   /* SYS_OPENDIR(child LBA, 16-bit) */
        bios(FSDIRBUF, 0, 0xFA);                /* FSDIRBUF: our page $FA00 again */
        walk(depth + 1);
        i = i + 1;
    }
    return 0;
}

int main() {
    char *arg;
    char dbuf[64];                           /* the directory part of a glob path */
    char abuf[128];                          /* dbuf/arg made absolute (CWD-prefixed);
                                              * abspath() does not bound its output, so
                                              * this must hold CWD (<=47, CWDPATH is 48
                                              * bytes) + '/' + the path word + NUL, and
                                              * the word can be nearly the whole 63-byte
                                              * shell LINEBUF */
    int rec;
    int i;
    int j;
    int m;
    int ls;
    int hasslash;
    int slashpos;
    int g;
    int nf;                                  /* 1 = the requested directory is missing */
    int filemode;                            /* 1 = arg named a file, not a directory */
    int shown;                               /* entries that passed the glob filter */

    arg = argstr();                          /* the command tail after "DIR" */
    rec = 0;
    szmode = 0;
    filemode = 0;
    gpat[0] = 0;
    while (*arg == 32) { arg = arg + 1; }    /* skip leading spaces */
    if (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H')) {
        puts("usage: DIR [-R] [-S] [path|glob]   list a dir; -S: size sort; glob: * ?");
        return 0;
    }
    /* option loop: -R/-r recurse, -S/-s size sort (each its own '-x' token) */
    while (*arg == '-' && (*(arg + 1) == 'R' || *(arg + 1) == 'r'
                        || *(arg + 1) == 'S' || *(arg + 1) == 's')) {
        if (*(arg + 1) == 'R' || *(arg + 1) == 'r') { rec = 1; }
        else { szmode = 1; }
        arg = arg + 2;
        while (*arg == 32) { arg = arg + 1; }
    }

    /* scan the path token: remember the last '/', note any glob char */
    hasslash = 0; slashpos = 0; g = 0; i = 0;
    while (arg[i] != 0 && arg[i] != 13 && arg[i] != 32) {
        if (arg[i] == '/') { hasslash = 1; slashpos = i; }
        if (arg[i] == '*' || arg[i] == '?') { g = 1; }
        i = i + 1;
    }

    nf = 0;
    if (g) {                                 /* glob: split into dir + pattern */
        ls = 0;
        if (hasslash) { ls = slashpos + 1; } /* leaf starts after the last '/' */
        j = 0;
        /* gpat is 16 bytes: 15 chars + NUL. A longer pattern is silently
         * truncated — it could never match a 12-char on-disk name anyway. */
        while (ls < i && j < 15) { gpat[j] = arg[ls]; j = j + 1; ls = ls + 1; }
        gpat[j] = 0;
        if (hasslash) {                      /* scan the named dir (incl trailing '/') */
            j = 0;
            while (j <= slashpos) { dbuf[j] = arg[j]; j = j + 1; }
            dbuf[j] = 0;
            abspath(abuf, dbuf);                           /* relative -> CWD-prefixed */
            if (bios(FOPENDIR, abuf, 0) & 256) { nf = 1; }   /* FOPENDIR(dir) */
        } else {
            bios(SYS_OPENCWD, 0, 0);              /* SYS_OPENCWD */
        }
    } else if (*arg == 0 || *arg == 13) {    /* no path -> current directory */
        bios(SYS_OPENCWD, 0, 0);                  /* SYS_OPENCWD (full 16-bit CWD LBA) */
    } else {                                 /* a path: try it as a directory... */
        abspath(abuf, arg);                  /* relative -> CWD-prefixed (FRESOLVE starts at root) */
        if (bios(FOPENDIR, abuf, 0) & 256) { /* ...not a dir -> list it as a single file: */
            filemode = 1;                    /*   filter the parent dir by the exact leaf */
            rec = 0;                         /*   (a file has no subtree to recurse) */
            ls = 0;
            if (hasslash) { ls = slashpos + 1; }
            j = 0;
            while (arg[ls] != 0 && arg[ls] != 13 && arg[ls] != 32 && j < 15) {
                gpat[j] = arg[ls]; j = j + 1; ls = ls + 1;   /* 15 chars + NUL max */
            }
            gpat[j] = 0;
            if (hasslash) {                  /* open the file's parent directory */
                j = 0;
                while (j <= slashpos) { dbuf[j] = arg[j]; j = j + 1; }
                dbuf[j] = 0;
                abspath(abuf, dbuf);
                if (bios(FOPENDIR, abuf, 0) & 256) { nf = 1; }
            } else {
                bios(SYS_OPENCWD, 0, 0);
            }
        }
    }
    if (nf) { puts("dir: not found"); return 1; }
    bios(FSDIRBUF, 0, 0xFA);                   /* FSDIRBUF: iterate in our own page $FA00 */

    if (rec) {
        walk(0);                             /* whole subtree, streamed (filtered) */
    } else {
        collect();                           /* single level: buffer + sort */
        i = 0;
        shown = 0;
        while (i < ecnt) {
            m = eidx[i];
            nameat(m);
            if (gpat[0] == 0 || gmatch(gpat, nbuf)) { shown = shown + 1; }
            show(0, eisd[m], elen[m], elen2[m]);       /* name + size; '/' marks a directory */
            i = i + 1;
        }
        /* a named file that survived FOPENDIR-fails but matched nothing in its
         * parent means the leaf doesn't actually exist -> report not found */
        if (filemode && shown == 0) { puts("dir: not found"); return 1; }
    }
    return 0;
}
