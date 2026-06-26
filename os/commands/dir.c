/* dir.c — the OS DIR command written as a C program for the P8X.
 *
 *     DIR [-R] [path | glob]
 *
 * Lists a directory: the path argument (via argstr() -> P2), or — with no
 * argument — the current working directory (OS syscall SYS_OPENCWD, no peeking
 * into OS internals). A loadable /BIN/DIR.BIN program.
 *
 *   DIR                 list the CWD
 *   DIR /BIN            list a directory by path
 *   DIR *.ASM           list CWD entries matching a glob (* and ?)
 *   DIR /BIN/*.BIN      glob within another directory
 *   DIR -R              recurse the whole subtree (two-space indent per level)
 *   DIR -R *.C          recurse, printing only entries matching the glob
 *
 * GLOB: if the path's last component contains '*' or '?', it is a pattern; the
 * part before the last '/' (or the CWD) is the directory to scan, and only
 * entries whose name matches the pattern (case-insensitive, via lib_glob's
 * gmatch) are printed. With -R the filter applies at every level while still
 * descending into all subdirectories.
 *
 * It streams one name at a time straight to stdout, so it is fully redirectable
 * and pipeable. Directory iteration (FNEXT) is moved off the BIOS sector buffer
 * SBUF onto our own page (FSDIRBUF $0145, page $FA00) so a write stream/pipe keeps
 * SBUF to itself. ($FA is high in the TPA, clear of the code: the size column's
 * putnum/ndigits/putsize pushed the native p8cc.c build past the old $EA00 page,
 * which then scribbled the iteration buffer onto the program's own tail.)
 *
 * Each line is a right-justified byte size, two spaces, then the name (a '/'
 * suffix marks a directory). Directories have no byte length, so their size
 * column is left blank. The size comes from FNEXT's FLEN ($7058 lo / $7059 hi),
 * a 16-bit count — fine for the small files this OS holds.
 *
 * BIOS: FOPENDIR=$0139 (P1=path), FOPENDIRAT=$0142 (A=low,LBA1=$7048 high),
 * FNEXT=$013C (-> FNAME $704A 12 space-padded, FFLAG $7070 file $01/dir $02,
 * start LBA byte0 $7047/byte1 $7048, FLEN $7058 lo/$7059 hi; C=1 at end),
 * FSDIRBUF=$0145.
 * OS: SYS_OPENCWD=$4012 (begin iterating the CWD, full 16-bit LBA).
 */
//#use glob   /* gmatch(pat, name): case-insensitive * ? matcher */

char nbuf[16];                               /* current entry name, NUL-terminated */
char gpat[16];                               /* glob pattern, or empty = no filter */

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

/* getname: nbuf <- FNAME ($704A, 12 space-padded), trailing pad trimmed. */
int getname() {
    int i;
    int c;
    i = 0;
    c = peek(0x704A + i);
    while (i < 12 && c != 32) {
        nbuf[i] = c;
        i = i + 1;
        c = peek(0x704A + i);
    }
    nbuf[i] = 0;
    return i;
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
 * FOPENDIR/FOPENDIRAT + FSDIRBUF). depth = indentation level. */
int walk(int depth) {
    int sub[64];            /* child subdirectory start LBAs, collected this level */
    int nsub;
    int r;
    int i;

    nsub = 0;
    r = bios(0x013C, 0, 0);                  /* FNEXT */
    while ((r & 256) == 0) {                  /* bit 8 = carry = end of directory */
        if (peek(0x704A) != '.') {            /* skip '.' and '..' (both lead with '.') */
            getname();
            show(depth, peek(0x7070) == 2,    /* print (filtered) name + size */
                 peek(0x7058) + peek(0x7059) * 256);
            if (peek(0x7070) == 2) {          /* always record subdirs for the pass */
                if (nsub < 64) {
                    sub[nsub] = peek(0x7047) + peek(0x7048) * 256;
                    nsub = nsub + 1;
                }
            }
        }
        r = bios(0x013C, 0, 0);
    }
    /* This level's FNEXT loop is closed; now descend into each recorded child. */
    i = 0;
    while (i < nsub) {
        poke(0x7048, sub[i] / 256);           /* FOPENDIRAT high byte (LBA1, $7048) */
        poke(0x7049, 0);
        bios(0x0142, 0, sub[i]);              /* FOPENDIRAT(child LBA): A=low, LBA1=high */
        bios(0x0145, 0, 0xFA);                /* FSDIRBUF: our page $FA00 again */
        walk(depth + 1);
        i = i + 1;
    }
    return 0;
}

int main() {
    char *arg;
    char dbuf[64];                           /* the directory part of a glob path */
    int rec;
    int r;
    int i;
    int j;
    int ls;
    int hasslash;
    int slashpos;
    int g;

    arg = argstr();                          /* the command tail after "DIR" */
    rec = 0;
    gpat[0] = 0;
    while (*arg == 32) { arg = arg + 1; }    /* skip leading spaces */
    if (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H')) {
        puts("usage: DIR [-R] [path|glob]   list a dir; glob: * ? in the last name");
        return 0;
    }
    if (*arg == '-' && (*(arg + 1) == 'R' || *(arg + 1) == 'r')) {
        rec = 1;                             /* -R / -r : recurse */
        arg = arg + 2;
        while (*arg == 32) { arg = arg + 1; }  /* then the optional path/glob */
    }

    /* scan the path token: remember the last '/', note any glob char */
    hasslash = 0; slashpos = 0; g = 0; i = 0;
    while (arg[i] != 0 && arg[i] != 13 && arg[i] != 32) {
        if (arg[i] == '/') { hasslash = 1; slashpos = i; }
        if (arg[i] == '*' || arg[i] == '?') { g = 1; }
        i = i + 1;
    }

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
            bios(0x0139, dbuf, 0);           /* FOPENDIR(dir) */
        } else {
            bios(0x4012, 0, 0);              /* SYS_OPENCWD */
        }
    } else if (*arg == 0 || *arg == 13) {    /* no path -> current directory */
        bios(0x4012, 0, 0);                  /* SYS_OPENCWD (full 16-bit CWD LBA) */
    } else {
        bios(0x0139, arg, 0);                /* FOPENDIR(path) */
    }
    bios(0x0145, 0, 0xFA);                   /* FSDIRBUF: iterate in our own page $FA00 */

    if (rec) {
        walk(0);                             /* whole subtree, streamed (filtered) */
    } else {
        r = bios(0x013C, 0, 0);              /* FNEXT — single-level loop */
        while ((r & 256) == 0) {             /* bit 8 = carry = end of directory */
            getname();
            show(0, peek(0x7070) == 2,       /* name + size; '/' marks a directory */
                 peek(0x7058) + peek(0x7059) * 256);
            r = bios(0x013C, 0, 0);
        }
    }
    return 0;
}
