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
    arg = argstr();                          /* raw arg tail; only -h is honored */
    while (*arg == 32) { arg = arg + 1; }    /* skip leading spaces (32 = ' ') */
    /* Accept -h or -H as the help flag; any other arg is ignored below. */
    if (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H')) {
        puts("usage: PWD   print the working directory path");
        return 0;
    }
    /* Ask the OS for the CWD via the ABI. Clobbers P1/P2 like all syscalls;
     * third arg unused. On return buf holds the NUL-terminated path. */
    bios(SYS_GETCWD, buf, 0);                    /* SYS_GETCWD -> buf */
    puts(buf);                                   /* puts() appends a newline */
    return 0;
}
