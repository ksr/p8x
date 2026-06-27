/* wc.c — count lines, words, and bytes of a file, a glob, or stdin (Unix `wc`).
 *
 *     RUN /BIN/WC.BIN FILE          -> "L W B"  (lines words bytes)
 *     RUN /BIN/WC.BIN *.LOG         -> combined count over every matching file
 *     RUN /BIN/WC.BIN <FILE         -> from a stdin redirect
 *     cmd | RUN /BIN/WC.BIN         -> counts the pipe
 *  (and, via implicit RUN + PATH, simply `WC FILE`, `WC *.LOG`, or `… | WC`).
 *
 * A stdin->stdout filter built on the shared open-input helper (lib_stdin): a
 * file or glob argument is read via that (a glob is read as ONE concatenated
 * stream — combined totals, like `CAT *.LOG | WC`), else it reads stdin. Counts
 * newlines (LF) as lines and whitespace-delimited runs as words. Counts are
 * 16-bit (the p8cc int), so they wrap above 65535 — fine for the small files
 * this OS holds.
 *
 * OS: getchar() is SYS_GETC; EOF is 65535. With no arg/`<file`/pipe, stdin is
 * the console and Ctrl-D ends input.
 */
//#use stdin   /* path[80], fromfile, nextc(), openarg() — file/glob/stdin input */

int putnum(int n) {                          /* print an unsigned decimal */
    if (n >= 10) { putnum(n / 10); }
    putchar(48 + n % 10);
    return 0;
}

int main() {
    char *arg;
    int c;
    int r;
    int lines;
    int words;
    int bytes;
    int inword;

    arg = argstr();
    while (*arg == 32) { arg = arg + 1; }
    if (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H')) {
        puts("usage: WC [file|glob]   count lines words bytes (file/glob or stdin)");
        return 0;
    }

    fromfile = 0;
    r = openarg(arg);                         /* file/glob, else stdin */
    if (r == 2) { puts("wc: not found"); return 1; }
    if (r == 1) { fromfile = 1; }

    lines = 0;
    words = 0;
    bytes = 0;
    inword = 0;
    c = nextc();
    while (c != 65535) {
        bytes = bytes + 1;
        if (c == 10) { lines = lines + 1; }
        if (c == 32 || c == 9 || c == 10 || c == 13) {
            inword = 0;
        } else {
            if (inword == 0) { words = words + 1; inword = 1; }
        }
        c = nextc();
    }
    putnum(lines); putchar(32);
    putnum(words); putchar(32);
    putnum(bytes); putchar(10);
    return 0;
}
