/* dir.c — the OS DIR command written as a C program for the P8X.
 *
 * Demonstrates that OS commands can be offloaded to loadable C `.BIN` programs:
 * it takes its path argument from the command tail (argstr() -> P2), iterates a
 * directory with the BIOS FOPENDIR/FNEXT calls via bios(), and detects the end
 * of the listing through the carry flag that bios() now surfaces in bit 8.
 *
 *     python3 compiler/p8cc.py compiler/examples/dir.c -o dir.asm
 *     python3 assembler/p8xasm.py dir.asm -o dir.bin --base 0xB000
 *     p8xfs put disk.img dir.bin --name DIR.BIN --load 0xB000 --exec 0xB000
 *     # on the P8X:   RUN DIR.BIN /BIN     (or just RUN DIR.BIN -> root)
 *
 * BIOS: FOPENDIR=$0139 (P1=path), FNEXT=$013C (-> FNAME at $9D4A; C=1 at end).
 */
int main() {
    char *arg;
    int r;
    int done;
    int i;
    int c;

    arg = argstr();                          /* the command tail after "DIR" */
    if (*arg == 0 || *arg == 13) { arg = "/"; }   /* no arg -> list the root  */

    bios(0x0139, arg, 0);                    /* FOPENDIR(path)               */
    done = 0;
    while (done == 0) {
        r = bios(0x013C, 0, 0);              /* FNEXT; bit 8 = carry = at end */
        if (r & 256) {
            done = 1;
        } else {
            i = 0;                            /* print FNAME ($9D4A, 12 bytes, */
            while (i < 12) {                  /* space-padded), trimming pad   */
                c = peek(0x9D4A + i);
                if (c != 32) putchar(c);
                i = i + 1;
            }
            putchar(10);
        }
    }
    return 0;
}
