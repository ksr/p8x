/* dir.c - the OS DIR command, a loadable /BIN/DIR.BIN program.  DIR [-R] [path]
 *   RUN /BIN/DIR.BIN /BIN     RUN /BIN/DIR.BIN -R / >LIST.TXT
 *
 * Lists the path argument (argstr() -> P2), or the CWD with no path (syscall
 * SYS_CWDLBA).  -R recurses, indenting two spaces per level (dirs marked '/').
 * Names stream straight to stdout, so DIR is redirectable/pipeable uncapped:
 * FNEXT iteration and the write stream would both clash in the BIOS buffer SBUF,
 * so FSDIRBUF moves iteration onto our own page ($E000, above $B000, below the
 * $FEFF stack).  -R keeps that streaming property.
 *
 * BIOS: FOPENDIR=$0139 (P1=path), FOPENDIRAT=$0142 (A=dir LBA), FNEXT=$013C
 * (-> FNAME $9D4A 12 bytes space-padded; FFLAG $9D70 = file 1 / dir 2; start LBA
 * byte0 $9D47; C=1 at end), FSDIRBUF=$0145 (A=page).  OS: SYS_CWDLBA=$4006.
 *
 * Recursion vs. the GLOBAL FNEXT cursor (DILBA/DICNT/DIIDX): opening a child dir
 * clobbers the parent's place.  So each level runs ONE FNEXT loop, streaming
 * names, and only RECORDS child subdirs' start LBAs into a small per-level array
 * (a dir holds <=64 entries, so it is bounded; output stays uncapped).  Only
 * after the loop closes do we re-open each child by LBA and recurse.  '.'/'..'
 * are skipped or it loops forever.
 *
 * NB: keep under 4 KB - the p8cc.c bootstrap reads source into a fixed
 * 4096-byte buffer, so longer comments would truncate the program.
 */

/* Print FNAME ($9D4A, 12 bytes space-padded), trimming the trailing pad. */
int putname() {
    int i;
    int c;
    i = 0;
    while (i < 12) {
        c = peek(0x9D4A + i);
        if (c != 32) { putchar(c); }
        i = i + 1;
    }
    return 0;
}

/* Recurse the directory already open (caller did FOPENDIR/AT + FSDIRBUF). */
int walk(int depth) {
    int sub[64];            /* child subdir start LBAs collected this level */
    int nsub;
    int r;
    int i;

    nsub = 0;
    r = bios(0x013C, 0, 0);                  /* FNEXT */
    while ((r & 256) == 0) {                  /* bit 8 = carry = end of dir */
        if (peek(0x9D4A) != '.') {            /* skip '.' and '..' */
            i = 0;
            while (i < depth) {               /* indent two spaces per level */
                putchar(32); putchar(32);
                i = i + 1;
            }
            putname();
            if (peek(0x9D70) == 2) {          /* FFLAG: directory */
                putchar('/');
                if (nsub < 64) {
                    sub[nsub] = peek(0x9D47); /* start LBA byte0 */
                    nsub = nsub + 1;
                }
            }
            putchar(10);
        }
        r = bios(0x013C, 0, 0);
    }
    /* loop closed; descend into each recorded child */
    i = 0;
    while (i < nsub) {
        bios(0x0142, 0, sub[i]);              /* FOPENDIRAT(child LBA) */
        bios(0x0145, 0, 0xE0);                /* FSDIRBUF: our page $E000 again */
        walk(depth + 1);
        i = i + 1;
    }
    return 0;
}

int main() {
    char *arg;
    int rec;
    int r;

    arg = argstr();                          /* the command tail after "DIR" */
    rec = 0;
    while (*arg == 32) { arg = arg + 1; }    /* skip leading spaces */
    if (*arg == '-' && (*(arg + 1) == 'R' || *(arg + 1) == 'r')) {
        rec = 1;                             /* -R / -r : recurse */
        arg = arg + 2;
        while (*arg == 32) { arg = arg + 1; }
    }

    if (*arg == 0 || *arg == 13) {           /* no path -> current directory */
        bios(0x0142, 0, bios(0x4006, 0, 0) & 255);   /* FOPENDIRAT(SYS_CWDLBA) */
    } else {
        bios(0x0139, arg, 0);                /* FOPENDIR(path) */
    }
    bios(0x0145, 0, 0xE0);                   /* FSDIRBUF: our own page $E000 */

    if (rec) {
        walk(0);
    } else {
        r = bios(0x013C, 0, 0);              /* FNEXT - single-level loop */
        while ((r & 256) == 0) {
            putname();
            putchar(10);
            r = bios(0x013C, 0, 0);
        }
    }
    return 0;
}
