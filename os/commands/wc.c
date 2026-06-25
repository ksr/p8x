/* wc.c — count lines, words, and bytes on stdin (the Unix `wc` filter).
 *
 *     RUN /BIN/WC.BIN <FILE         -> "L W B"  (lines words bytes)
 *     cmd | RUN /BIN/WC.BIN         -> counts the pipe
 *  (and, via implicit RUN + PATH, simply `WC <FILE` or `… | WC`).
 *
 * A pure stdin->stdout filter: reads getchar() to EOF (-1), counting newlines
 * (LF) as lines and whitespace-delimited runs as words. Counts are 16-bit (the
 * p8cc int), so they wrap above 65535 — fine for the small files this OS holds.
 *
 * OS: getchar() is SYS_GETC; EOF is 65535. With no `<file`/pipe, stdin is the
 * console and Ctrl-D ends input.
 */
int putnum(int n) {                          /* print an unsigned decimal */
    if (n >= 10) { putnum(n / 10); }
    putchar(48 + n % 10);
    return 0;
}

int main() {
    char *arg;
    int c;
    int lines;
    int words;
    int bytes;
    int inword;

    arg = argstr();
    while (*arg == 32) { arg = arg + 1; }
    if (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H')) {
        puts("usage: WC   count lines words bytes on stdin");
        return 0;
    }

    lines = 0;
    words = 0;
    bytes = 0;
    inword = 0;
    c = getchar();
    while (c != 65535) {
        bytes = bytes + 1;
        if (c == 10) { lines = lines + 1; }
        if (c == 32 || c == 9 || c == 10 || c == 13) {
            inword = 0;
        } else {
            if (inword == 0) { words = words + 1; inword = 1; }
        }
        c = getchar();
    }
    putnum(lines); putchar(32);
    putnum(words); putchar(32);
    putnum(bytes); putchar(10);
    return 0;
}
