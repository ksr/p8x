/* cat.c — copy stdin to stdout, the canonical filter, demonstrating shell input
 * redirection.  getchar() returns -1 (65535) at end of input.
 *
 *     RUN CAT.BIN <FILE         -> print FILE to the console
 *     RUN CAT.BIN <IN >OUT      -> copy IN to OUT
 *
 * The OS binds stdin/stdout (SYS_GETC/SYS_PUTC); cat is oblivious to whether
 * they are the console or files.
 */
int main() {
    int c;
    c = getchar();
    while (c != 65535) {
        putchar(c);
        c = getchar();
    }
    return 0;
}
