/* tree.c — depth-first indented listing of the directory tree (Unix `tree`).
 *
 *     TREE                 the whole tree under the CWD
 *
 * The same recursion as DIR -R: each level streams its entries (two spaces of
 * indent per level, a trailing '/' on directories) while recording child
 * subdirectory LBAs, then descends — because FNEXT's cursor is global BIOS
 * state. Searches the CWD; per-level children capped at 24.
 *
 * BIOS: FOPENDIRAT=$0142, FSDIRBUF=$0145, FNEXT=$013C (name->$9D4A, flag->$9D70,
 * start LBA->$9D47). OS: SYS_CWDLBA=$4006.
 */
int putname() {                              /* FNAME ($9D4A, 12, space-padded) */
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

int walk(int depth) {
    int sub[24];
    int nsub;
    int r;
    int i;

    nsub = 0;
    r = bios(0x013C, 0, 0);                  /* FNEXT */
    while ((r & 256) == 0) {
        if (peek(0x9D4A) != '.') {           /* skip '.' and '..' */
            i = 0;
            while (i < depth) { putchar(32); putchar(32); i = i + 1; }
            putname();
            if (peek(0x9D70) == 2) {         /* directory */
                putchar('/');
                if (nsub < 24) { sub[nsub] = peek(0x9D47) + peek(0x9D48) * 256; nsub = nsub + 1; }
            }
            putchar(10);
        }
        r = bios(0x013C, 0, 0);
    }
    i = 0;                                    /* descend into recorded children */
    while (i < nsub) {
        poke(0x9D48, sub[i] / 256);          /* FOPENDIRAT high byte (LBA1) */
        poke(0x9D49, 0);
        bios(0x0142, 0, sub[i]);             /* FOPENDIRAT(child): A=low, LBA1=high */
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
    bios(0x4012, 0, 0);                      /* SYS_OPENCWD: iterate CWD (16-bit LBA) */
    bios(0x0145, 0, 0xEA);
    walk(0);
    return 0;
}
