/* pwd.c — the OS PWD command written as a C program for the P8X.
 *
 * Prints the current working directory by asking the OS for it through the
 * SYS_GETCWD syscall ($4003), which copies the CWD path string into the
 * caller's buffer.  No peeking into OS RAM — the path comes through the ABI.
 *
 *     python3 compiler/p8cc.py os/commands/pwd.c -o pwd.asm
 *     # on the P8X:   RUN PWD.BIN     ->   /SUB
 *
 * OS: SYS_GETCWD = $4003 (copies the CWD path, incl. NUL, into P1).
 */
char buf[52];                                /* CWDPATH is up to 48 bytes + NUL */
int main() {
    bios(0x4003, buf, 0);                    /* SYS_GETCWD -> buf */
    puts(buf);
    return 0;
}
