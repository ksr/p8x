/* tree.c — depth-first indented listing of the directory tree (Unix `tree`).
 *
 *     TREE                 the whole tree under the CWD
 *
 * The same recursion as DIR -R: each level streams its entries (two spaces of
 * indent per level, a trailing '/' on directories) while recording child
 * subdirectory LBAs, then descends — because FNEXT's cursor is global BIOS
 * state. Searches the CWD; per-level children capped at 24.
 *
 * BIOS: FOPENDIRAT=$0142, FSDIRBUF=$0145, FNEXT=$013C (name->$704A, flag->$7070,
 * start LBA->$7047). OS: SYS_CWDLBA=$2006. Entry fields read via SYS_DIRENTRY.
 */
//#use dirent   /* de_read/de_isdir/de_isdot/de_lba/de_opendir: entry via syscall */

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

int walk(int depth) {
    int sub[24];
    int nsub;
    int r;
    int i;

    nsub = 0;
    r = bios(0x013C, 0, 0);                  /* FNEXT */
    while ((r & 256) == 0) {
        de_read();                           /* snapshot the entry (SYS_DIRENTRY) */
        if (de_isdot() == 0) {               /* skip '.' and '..' */
            i = 0;
            while (i < depth) { putchar(32); putchar(32); i = i + 1; }
            putname();
            if (de_isdir()) {                /* directory */
                putchar('/');
                if (nsub < 24) { sub[nsub] = de_lba(); nsub = nsub + 1; }
            }
            putchar(10);
        }
        r = bios(0x013C, 0, 0);
    }
    i = 0;                                    /* descend into recorded children */
    while (i < nsub) {
        de_opendir(sub[i]);                  /* SYS_OPENDIR(child LBA, 16-bit) */
        bios(0x0145, 0, 0xEA);               /* FSDIRBUF: our page */
        walk(depth + 1);
        i = i + 1;
    }
    return 0;
}

int main() {
    char *a;
    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H')) {
        puts("usage: TREE   depth-first indented listing of the CWD tree");
        return 0;
    }
    bios(0x2012, 0, 0);                      /* SYS_OPENCWD: iterate CWD (16-bit LBA) */
    bios(0x0145, 0, 0xEA);
    walk(0);
    return 0;
}
