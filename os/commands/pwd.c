/* pwd.c — the OS PWD command written as a C program for the P8X.
 *
 * Prints the current working directory by asking the OS for it through the
 * SYS_GETCWD syscall ($2003), which copies the CWD path string into the
 * caller's buffer.  No peeking into OS RAM — the path comes through the ABI.
 *
 *     python3 compiler/p8cc.py os/commands/pwd.c -o pwd.asm
 *     # on the P8X:   RUN PWD.BIN     ->   /SUB
 *
 * OS: SYS_GETCWD = $2003 (copies the CWD path, incl. NUL, into P1).
 */
//#use abi     /* named BIOS/OS addresses: FOPEN, FGETB, SYS_GETCWD, RDBUF, ... */

char buf[52];                                /* CWDPATH is up to 48 bytes + NUL */
int main() {
    char *arg;
    arg = argstr();                          /* -h -> usage, then exit */
    while (*arg == 32) { arg = arg + 1; }
    if (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H')) {
        puts("usage: PWD   print the working directory path");
        return 0;
    }
    bios(SYS_GETCWD, buf, 0);                    /* SYS_GETCWD -> buf */
    puts(buf);
    return 0;
}
