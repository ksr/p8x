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
 * column is left blank. The size comes from FNEXT's FLEN ($7058 lo / $7059 hi),
 * a 16-bit count — fine for the small files this OS holds. p8cc's < / > are
 * unsigned 16-bit, so size sorting is correct up to 65535 bytes.
 *
 * BIOS: FOPENDIR=$0139 (P1=path), FOPENDIRAT=$0142 (A=low,LBA1=$7048 high),
 * FNEXT=$013C (-> FNAME $704A 12 space-padded, FFLAG $7070 file $01/dir $02,
 * start LBA byte0 $7047/byte1 $7048, FLEN $7058 lo/$7059 hi; C=1 at end),
 * FSDIRBUF=$0145.
 * OS: SYS_OPENCWD=$4012 (begin iterating the CWD, full 16-bit LBA).
 */
//#use glob     /* gmatch(pat, name): case-insensitive * ? matcher */
//#use dirent   /* de_read/de_isdir/de_len/de_lba/de_opendir: entry via syscall */
//#use apath    /* abspath(out, a): CWD-prefix a relative path (FRESOLVE starts at root) */

char nbuf[16];                               /* current entry name, NUL-terminated */
char gpat[16];                               /* glob pattern, or empty = no filter */

/* Per-directory entry buffers, filled by collect() and reused at every recursion
 * level (a level is printed before its children overwrite them). Cap 64 = a
 * fresh directory extent (4 sectors * 16 entries). */
char enam[768];                              /* 64 names, 12 space-padded bytes each */
int  elen[64];                               /* byte length (0 for dirs); 16-bit */
char eisd[64];                               /* 1 = directory (char: house rule — */
int  elba[64];                               /* start LBA (for -R descent); 16-bit */
char eidx[64];                               /* sorted print order (indices 0..63; a */
                                             /* char, not int: p8cc int arrays as a */
                                             /* sort permutation misbehave — see the */
                                             /* os/commands/README.md p8cc notes) */
int  ecnt;                                   /* entries collected this level */
int  szmode;                                 /* 1 = -S size sort, 0 = name sort */

/* putnum: print n as an unsigned decimal (recurses for the high digits). */
int putnum(int n) {
    if (n >= 10) { putnum(n / 10); }
    putchar(48 + n % 10);
    return 0;
}

/* ndigits: number of decimal digits in n (>=1, so 0 prints as one digit). */
int ndigits(int n) {
    int d;
    d = 1;
    while (n >= 10) { n = n / 10; d = d + 1; }
    return d;
}

/* putsize: a 6-wide size column. Files: the byte count, right-justified.
 * Directories (isdir): six blanks, since a directory has no byte length. */
int putsize(int isdir, int sz) {
    int k;
    if (isdir) {
        k = 0;
        while (k < 6) { putchar(32); k = k + 1; }
        return 0;
    }
    k = ndigits(sz);
    while (k < 6) { putchar(32); k = k + 1; }     /* pad to width 6 */
    putnum(sz);
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

/* skey: the sort size-key for entry m — a directory has no size, so it counts
 * as 0 (sorts after every file under largest-first). */
int skey(int m) {
    if (eisd[m]) { return 0; }
    return elen[m];
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
    int ka;
    int kb;
    if (szmode) {
        ka = skey(a);
        kb = skey(b);
        if (ka > kb) { return 1; }
        if (ka < kb) { return 0; }
        return namecmp(a, b) == 1;
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
    r = bios(0x013C, 0, 0);                  /* FNEXT */
    while ((r & 256) == 0) {                  /* bit 8 = carry = end of directory */
        de_read();                            /* snapshot the entry (SYS_DIRENTRY) */
        if (de_isdot() == 0) {                /* skip '.' and '..' */
            if (k < 64) {
                base = k * 12;
                i = 0;
                while (i < 12) { enam[base + i] = de[i]; i = i + 1; }
                if (de_isdir()) { eisd[k] = 1; elen[k] = 0; }
                else            { eisd[k] = 0; elen[k] = de_len(); }
                elba[k] = de_lba();
                k = k + 1;
            }
        }
        r = bios(0x013C, 0, 0);
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
int show(int depth, int isdir, int sz) {
    int i;
    if (gpat[0] != 0 && gmatch(gpat, nbuf) == 0) { return 0; }   /* filtered out */
    putsize(isdir, sz);
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
        show(depth, eisd[m], elen[m]);        /* print (filtered) name + size */
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
        bios(0x0145, 0, 0xFA);                /* FSDIRBUF: our page $FA00 again */
        walk(depth + 1);
        i = i + 1;
    }
    return 0;
}

int main() {
    char *arg;
    char dbuf[64];                           /* the directory part of a glob path */
    char abuf[80];                           /* dbuf/arg made absolute (CWD-prefixed) */
    int rec;
    int i;
    int j;
    int m;
    int ls;
    int hasslash;
    int slashpos;
    int g;
    int nf;                                  /* 1 = the requested directory is missing */

    arg = argstr();                          /* the command tail after "DIR" */
    rec = 0;
    szmode = 0;
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
        while (ls < i) { gpat[j] = arg[ls]; j = j + 1; ls = ls + 1; }
        gpat[j] = 0;
        if (hasslash) {                      /* scan the named dir (incl trailing '/') */
            j = 0;
            while (j <= slashpos) { dbuf[j] = arg[j]; j = j + 1; }
            dbuf[j] = 0;
            abspath(abuf, dbuf);                           /* relative -> CWD-prefixed */
            if (bios(0x0139, abuf, 0) & 256) { nf = 1; }   /* FOPENDIR(dir) */
        } else {
            bios(0x4012, 0, 0);              /* SYS_OPENCWD */
        }
    } else if (*arg == 0 || *arg == 13) {    /* no path -> current directory */
        bios(0x4012, 0, 0);                  /* SYS_OPENCWD (full 16-bit CWD LBA) */
    } else {                                 /* FOPENDIR(abs path); carry = missing/not a dir */
        abspath(abuf, arg);                  /* relative -> CWD-prefixed (FRESOLVE starts at root) */
        if (bios(0x0139, abuf, 0) & 256) { nf = 1; }
    }
    if (nf) { puts("dir: not found"); return 1; }
    bios(0x0145, 0, 0xFA);                   /* FSDIRBUF: iterate in our own page $FA00 */

    if (rec) {
        walk(0);                             /* whole subtree, streamed (filtered) */
    } else {
        collect();                           /* single level: buffer + sort */
        i = 0;
        while (i < ecnt) {
            m = eidx[i];
            nameat(m);
            show(0, eisd[m], elen[m]);       /* name + size; '/' marks a directory */
            i = i + 1;
        }
    }
    return 0;
}
