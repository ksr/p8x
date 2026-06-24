/* dir.c — the OS DIR command written as a C program for the P8X.
 *
 * Lists a directory: the path given as the argument (argstr() -> P2), or — with
 * no argument — the current working directory (via the OS syscall SYS_CWDLBA,
 * no peeking into OS internals). A loadable /BIN/DIR.BIN program.
 *
 * It collects the whole listing into a buffer FIRST, then prints it. That is
 * what lets it be redirected/piped (RUN DIR.BIN >X, DIR.BIN | ...): directory
 * iteration (FNEXT) and the output write stream both use the BIOS sector buffer
 * SBUF, so they must not interleave — so iterate fully, then emit.
 *
 *     python3 compiler/p8cc.py os/commands/dir.c -o dir.asm
 *     python3 assembler/p8xasm.py dir.asm -o dir.bin --base 0xB000
 *     p8xfs put disk.img dir.bin --name /BIN/DIR.BIN --load 0xB000 --exec 0xB000
 *     # on the P8X:   RUN /BIN/DIR.BIN /BIN     (or RUN /BIN/DIR.BIN >LIST.TXT)
 *
 * BIOS: FOPENDIR=$0139 (P1=path), FOPENDIRAT=$0142 (A=dir LBA), FNEXT=$013C
 * (-> FNAME at $9D4A, 12 bytes space-padded; C=1 at end).  OS: SYS_CWDLBA=$4006.
 */
char out[1024];                              /* the collected listing */
int main() {
    char *arg;
    int r;
    int i;
    int c;
    int n;

    arg = argstr();                          /* the command tail after "DIR" */
    if (*arg == 0 || *arg == 13) {           /* no arg -> the current directory */
        bios(0x0142, 0, bios(0x4006, 0, 0) & 255);   /* FOPENDIRAT(SYS_CWDLBA) */
    } else {
        bios(0x0139, arg, 0);                /* FOPENDIR(path) */
    }

    n = 0;                                   /* collect names while iterating */
    r = bios(0x013C, 0, 0);                  /* FNEXT */
    while ((r & 256) == 0) {                 /* bit 8 = carry = end of directory */
        i = 0;
        while (i < 12) {                     /* FNAME at $9D4A, trim trailing pad */
            c = peek(0x9D4A + i);
            if (c != 32 && n < 1020) { out[n] = c; n = n + 1; }
            i = i + 1;
        }
        if (n < 1020) { out[n] = 10; n = n + 1; }     /* newline */
        r = bios(0x013C, 0, 0);
    }
    out[n] = 0;

    i = 0;                                   /* now emit — no FNEXT in flight */
    while (out[i] != 0) { putchar(out[i]); i = i + 1; }
    return 0;
}
