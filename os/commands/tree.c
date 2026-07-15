/* tree.c — depth-first indented listing of the directory tree (Unix `tree`).
 *
 *     TREE                 the whole tree under the CWD
 *
 * The same recursion as DIR -R: each level streams its entries (two spaces of
 * indent per level, a trailing '/' on directories) while recording child
 * subdirectory LBAs, then descends — because FNEXT's cursor is global BIOS
 * state. Searches the CWD; per-level children capped at 24.
 *
 * BIOS: FNEXT=$013C (C=1 at end), FSDIRBUF=$0145 (aim FNEXT's buffer at a page).
 * OS: SYS_OPENCWD=$2012. Entry fields come from the de_* helpers (SYS_DIRENTRY
 * $201B / SYS_OPENDIR $201E), never from raw BIOS scratch addresses.
 */
//#use dirent   /* de_read/de_isdir/de_isdot/de_lba/de_opendir: entry via syscall */
//#use abi     /* named BIOS/OS addresses: FOPEN, FGETB, SYS_GETCWD, RDBUF, ... */

/* putname — print the current dirent's 12-char name (de[0..11], space-padded),
 * dropping the padding spaces (ASCII 32) so only the real name is emitted.
 * No newline. Reads global de[]; clobbers nothing the caller relies on. */
int putname() {                              /* de[0..11] (space-padded) */
    int i;
    int c;
    i = 0;
    while (i < 12) {
        c = de[i] & 255;
        if (c != 32) { putchar(c); }
        i = i + 1;
    }
    return 0;
}

/* walk — list one directory level, then recurse into its subdirectories.
 *   depth = indent level (0 = CWD root). Precondition: the caller has already
 *   opened the directory to iterate and pointed FSDIRBUF at our scratch page,
 *   so FNEXT returns THIS directory's entries.
 * Two-pass by necessity: FNEXT's read cursor is a single global BIOS state, so
 * we cannot descend mid-scan without clobbering it. Pass 1 streams every entry
 * and stashes child subdirectory LBAs in sub[]; pass 2 re-opens each child and
 * recurses. Children beyond 24 per level are silently dropped (sub[] is fixed).
 * Recurses via SYS_DIRENTRY/FNEXT; clobbers de[] and the global FNEXT cursor. */
int walk(int depth) {
    int sub[24];                            /* child subdir LBAs, this level */
    int nsub;                               /* count of children recorded */
    int r;                                  /* FNEXT status; bit 8 = end-of-dir */
    int i;

    nsub = 0;
    r = bios(FNEXT, 0, 0);                  /* FNEXT: advance to first entry */
    while ((r & 256) == 0) {                /* bit 8 clear = a valid entry */
        de_read();                           /* snapshot the entry (SYS_DIRENTRY) */
        if (de_isdot() == 0) {               /* skip '.' and '..' */
            i = 0;                           /* two spaces of indent per level */
            while (i < depth) { putchar(32); putchar(32); i = i + 1; }
            putname();
            if (de_isdir()) {                /* directory */
                putchar('/');
                if (nsub < 24) { sub[nsub] = de_lba(); nsub = nsub + 1; }
            }
            putchar(10);
        }
        r = bios(FNEXT, 0, 0);
    }
    i = 0;                                    /* pass 2: descend into children */
    while (i < nsub) {
        de_opendir(sub[i]);                  /* SYS_OPENDIR(child LBA, 16-bit) */
        bios(FSDIRBUF, 0, 0xEA);               /* re-aim FNEXT at page $EA scratch */
        walk(depth + 1);
        i = i + 1;
    }
    return 0;
}

/* main — parse args (only -h/-H for help), then open the CWD and walk it.
 * TREE takes no path operand; it always lists the current directory. */
int main() {
    char *a;
    a = argstr();
    while (*a == 32) { a = a + 1; }          /* skip leading spaces */
    if (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H')) {
        puts("usage: TREE   depth-first indented listing of the CWD tree");
        return 0;
    }
    bios(SYS_OPENCWD, 0, 0);                      /* SYS_OPENCWD: iterate CWD (16-bit LBA) */
    bios(FSDIRBUF, 0, 0xEA);                      /* aim FNEXT at page $EA scratch */
    walk(0);
    return 0;
}
