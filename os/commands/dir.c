/* dir.c — the OS DIR command written as a C program for the P8X.
 *
 * Lists a directory: the path given as the argument (argstr() -> P2), or — with
 * no argument — the current working directory (via the OS syscall SYS_CWDLBA,
 * no peeking into OS internals). A loadable /BIN/DIR.BIN program.
 *
 * It streams one name at a time straight to stdout, so it is fully redirectable
 * and pipeable with no size limit. Directory iteration (FNEXT) and the output
 * write stream would otherwise both buffer through the BIOS sector buffer SBUF
 * and corrupt each other; FSDIRBUF ($0145) moves iteration onto our own
 * page-aligned buffer (DBUF below) so the write stream keeps SBUF to itself.
 *
 *     python3 compiler/p8cc.py os/commands/dir.c -o dir.asm
 *     python3 assembler/p8xasm.py dir.asm -o dir.bin --base 0xB000
 *     p8xfs put disk.img dir.bin --name /BIN/DIR.BIN --load 0xB000 --exec 0xB000
 *     # on the P8X:   RUN /BIN/DIR.BIN /BIN     (or RUN /BIN/DIR.BIN >LIST.TXT)
 *
 * BIOS: FOPENDIR=$0139 (P1=path), FOPENDIRAT=$0142 (A=dir LBA), FNEXT=$013C
 * (-> FNAME at $9D4A, 12 bytes space-padded; C=1 at end), FSDIRBUF=$0145
 * (A=buffer page).  OS: SYS_CWDLBA=$4006.
 *
 * The iteration buffer is a fixed 512-byte, page-aligned scratch buffer high in
 * the transient program area ($E000, page $E0): well above this program's
 * code/globals at $B000 and well below the stack at $FEFF, and page-aligned as
 * FSDIRBUF requires. (p8cc has no preprocessor, so it is written as a literal.)
 */
int main() {
    char *arg;
    int r;
    int i;
    int c;

    arg = argstr();                          /* the command tail after "DIR" */
    if (*arg == 0 || *arg == 13) {           /* no arg -> the current directory */
        bios(0x0142, 0, bios(0x4006, 0, 0) & 255);   /* FOPENDIRAT(SYS_CWDLBA) */
    } else {
        bios(0x0139, arg, 0);                /* FOPENDIR(path) */
    }
    bios(0x0145, 0, 0xE0);                   /* FSDIRBUF: iterate in our own page $E000 */

    r = bios(0x013C, 0, 0);                  /* FNEXT */
    while ((r & 256) == 0) {                 /* bit 8 = carry = end of directory */
        i = 0;
        while (i < 12) {                     /* FNAME at $9D4A, trim trailing pad */
            c = peek(0x9D4A + i);
            if (c != 32) { putchar(c); }
            i = i + 1;
        }
        putchar(10);                         /* newline */
        r = bios(0x013C, 0, 0);
    }
    return 0;
}
