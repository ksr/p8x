/* find.c — recursively list files under the CWD whose name contains a pattern.
 * A small `find . -name '*PAT*'`.
 *
 *     FIND .TXT            every path under the CWD whose name contains ".TXT"
 *     FIND BIN             ... contains "BIN"
 *
 * Walks the current directory tree depth-first and prints the full path of every
 * entry (file or directory) whose name contains the (literal substring) pattern.
 * Searches the CWD only — no path argument yet (backlog). The FNEXT cursor is
 * global BIOS state, so each level streams its entries while recording child
 * subdirectory LBAs *and names*, then descends (same shape as DIR -R). Per-level
 * children capped at 24; path depth bounded by the stack.
 *
 * BIOS: FOPENDIRAT=$0142, FSDIRBUF=$0145, FNEXT=$013C (name->$9D4A, flag->$9D70,
 * start LBA->$9D47). OS: SYS_GETCWD=$4003, SYS_CWDLBA=$4006.
 */
char cur[256];                               /* path of the directory being walked */
char nm[16];                                 /* current entry name (trimmed) */
char pat[64];                                /* search substring */

int contains(char *h, char *n) {             /* 1 if n is a substring of h */
    int i;
    int j;
    i = 0;
    while (h[i] != 0) {
        j = 0;
        while (n[j] != 0 && h[i + j] == n[j]) { j = j + 1; }
        if (n[j] == 0) { return 1; }
        i = i + 1;
    }
    return 0;
}

int rdname() {                               /* FNAME ($9D4A, 12, space-padded) -> nm */
    int i;
    int k;
    int c;
    k = 0;
    i = 0;
    while (i < 12) {
        c = peek(0x9D4A + i) & 255;
        if (c != 32) { nm[k] = c; k = k + 1; }
        i = i + 1;
    }
    nm[k] = 0;
    return k;
}

int walk(int plen) {                          /* plen = length of cur (no trailing /) */
    int clba[24];
    char cn[384];                            /* 24 child names x 16 */
    int nsub;
    int r;
    int i;
    int k;
    int oldp;

    nsub = 0;
    r = bios(0x013C, 0, 0);                  /* FNEXT */
    while ((r & 256) == 0) {
        if (peek(0x9D4A) != '.') {           /* skip '.' / '..' */
            rdname();
            if (contains(nm, pat)) {         /* print cur + '/' + nm */
                i = 0;
                while (i < plen) { putchar(cur[i]); i = i + 1; }
                if (plen != 1 || cur[0] != '/') { putchar('/'); }
                i = 0;
                while (nm[i] != 0) { putchar(nm[i]); i = i + 1; }
                putchar(10);
            }
            if (peek(0x9D70) == 2 && nsub < 24) {   /* a subdirectory -> record it */
                clba[nsub] = peek(0x9D47) + peek(0x9D48) * 256;   /* 16-bit child LBA */
                k = 0;
                while (nm[k] != 0) { cn[nsub * 16 + k] = nm[k]; k = k + 1; }
                cn[nsub * 16 + k] = 0;
                nsub = nsub + 1;
            }
        }
        r = bios(0x013C, 0, 0);
    }

    i = 0;                                    /* descend into each recorded child */
    while (i < nsub) {
        poke(0x9D48, clba[i] / 256);         /* FOPENDIRAT high byte (LBA1) */
        poke(0x9D49, 0);
        bios(0x0142, 0, clba[i]);            /* FOPENDIRAT(child): A=low, LBA1=high */
        bios(0x0145, 0, 0xE0);               /* FSDIRBUF: our page */
        oldp = plen;
        if (plen != 1 || cur[0] != '/') { cur[plen] = '/'; plen = plen + 1; }
        k = 0;
        while (cn[i * 16 + k] != 0) { cur[plen] = cn[i * 16 + k]; plen = plen + 1; k = k + 1; }
        cur[plen] = 0;
        walk(plen);
        cur[oldp] = 0;                       /* restore the prefix */
        plen = oldp;
        i = i + 1;
    }
    return 0;
}

int main() {
    char *a;
    int i;
    int plen;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: FIND pattern   paths under the CWD whose name contains pattern");
        return 0;
    }
    i = 0;
    while (a[i] != 0 && a[i] != 32 && a[i] != 13 && i < 63) { pat[i] = a[i]; i = i + 1; }
    pat[i] = 0;

    bios(0x4003, cur, 0);                    /* cur = CWD path */
    plen = 0;
    while (cur[plen] != 0) { plen = plen + 1; }
    bios(0x4012, 0, 0);                      /* SYS_OPENCWD: iterate CWD (16-bit LBA) */
    bios(0x0145, 0, 0xE0);
    walk(plen);
    return 0;
}
