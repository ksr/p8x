/* dir.c — the OS DIR command written as a C program for the P8X.
 *
 *     DIR [-R] [path]
 *
 * Lists a directory: the path given as the argument (argstr() -> P2), or — with
 * no argument — the current working directory (via the OS syscall SYS_CWDLBA,
 * no peeking into OS internals). A loadable /BIN/DIR.BIN program.
 *
 * With -R it recurses, printing the whole subtree indented two spaces per level
 * (directories flagged with a trailing '/'). Without it, exactly the old
 * single-level listing.
 *
 * It streams one name at a time straight to stdout, so it is fully redirectable
 * and pipeable with no size limit. Directory iteration (FNEXT) and the output
 * write stream would otherwise both buffer through the BIOS sector buffer SBUF
 * and corrupt each other; FSDIRBUF ($0145) moves iteration onto our own
 * page-aligned buffer (DBUF below) so the write stream keeps SBUF to itself.
 * Recursion keeps that streaming property: -R never buffers the listing.
 *
 *     python3 compiler/p8cc.py os/commands/dir.c -o dir.asm
 *     python3 assembler/p8xasm.py dir.asm -o dir.bin --base 0xB000
 *     p8xfs put disk.img dir.bin --name /BIN/DIR.BIN --load 0xB000 --exec 0xB000
 *     # on the P8X:   RUN /BIN/DIR.BIN /BIN     (or RUN /BIN/DIR.BIN -R / >LIST.TXT)
 *
 * BIOS: FOPENDIR=$0139 (P1=path), FOPENDIRAT=$0142 (A=dir LBA), FNEXT=$013C
 * (-> FNAME at $9D4A, 12 bytes space-padded; FFLAG at $9D70 = file $01 / dir
 * $02; start LBA in LBA byte0 at $9D47; C=1 at end), FSDIRBUF=$0145
 * (A=buffer page).  OS: SYS_CWDLBA=$4006.
 *
 * The iteration buffer is a fixed 512-byte, page-aligned scratch buffer high in
 * the transient program area ($E000, page $E0): well above this program's
 * code/globals at $B000 and well below the stack at $FEFF, and page-aligned as
 * FSDIRBUF requires. (p8cc has no preprocessor, so it is written as a literal.)
 *
 * RECURSION & the global FNEXT cursor. FNEXT's iteration state (DILBA/DICNT/
 * DIIDX/DIBUFH) is GLOBAL BIOS state: opening a child directory clobbers the
 * parent's place. So at each level we run exactly ONE FNEXT loop — streaming
 * every entry's name as we go — and during that loop only RECORD the child
 * subdirectories' start LBAs into a small per-level array. A P8XFS directory
 * holds at most 64 entries, so that array is bounded (<=64) no matter how big
 * the tree is; the output itself still streams uncapped. After the loop closes
 * we re-open each recorded child by LBA (FOPENDIRAT + FSDIRBUF) and recurse —
 * the parent's cursor is already spent, so clobbering it is harmless, and the
 * shared $E000 buffer is free to reuse because the parent no longer reads it.
 * walk() is genuinely recursive (one C-stack frame per level, sub[] local to
 * each); '.'/'..' are skipped or it would descend forever.
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
        if (peek(0x9D4A) != '.') {            /* skip '.' and '..' (both lead with '.') */
            i = 0;
            while (i < depth) {               /* indent two spaces per level */
                putchar(32); putchar(32);
                i = i + 1;
            }
            putname();
            if (peek(0x9D70) == 2) {          /* FFLAG: directory */
                putchar('/');
                if (nsub < 64) {              /* record child LBA for the recursion pass */
                    sub[nsub] = peek(0x9D47); /* start LBA, byte0 (subdir LBAs < 256) */
                    nsub = nsub + 1;
                }
            }
            putchar(10);                      /* newline */
        }
        r = bios(0x013C, 0, 0);
    }
    /* This level's FNEXT loop is closed; now descend into each recorded child. */
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
        while (*arg == 32) { arg = arg + 1; }  /* then the optional path */
    }

    if (*arg == 0 || *arg == 13) {           /* no path -> current directory */
        bios(0x0142, 0, bios(0x4006, 0, 0) & 255);   /* FOPENDIRAT(SYS_CWDLBA) */
    } else {
        bios(0x0139, arg, 0);                /* FOPENDIR(path) */
    }
    bios(0x0145, 0, 0xE0);                   /* FSDIRBUF: iterate in our own page $E000 */

    if (rec) {
        walk(0);                             /* whole subtree, streamed */
    } else {
        r = bios(0x013C, 0, 0);              /* FNEXT — original single-level loop */
        while ((r & 256) == 0) {             /* bit 8 = carry = end of directory */
            putname();
            putchar(10);                     /* newline */
            r = bios(0x013C, 0, 0);
        }
    }
    return 0;
}
