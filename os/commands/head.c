/* head.c — print the first N lines of a file (or stdin). Unix `head`.
 *
 *     HEAD file            first 10 lines of file
 *     HEAD -5 file         first 5 lines
 *     cmd | HEAD           first 10 lines of a pipe
 *     HEAD <file           first 10 lines from a stdin redirect
 *
 * Reads a named file if given (opened like cat: absolute path via SYS_GETCWD +
 * FRESOLVE/FOPEN, buffer at $FC00), else stdin. Line count defaults to 10, or
 * -N sets it. A line ends at LF; CR is passed through. EOF = 65535.
 */
//#use stdin   /* path[80], fromfile, nextc(), openarg() */

int main() {
    char *a;         /* walks the raw argument string */
    int n;           /* number of lines to print (the N in head -N) */
    int lines;       /* lines emitted so far */
    int c;           /* current input char, or 65535 (EOF) from nextc() */
    int r;           /* openarg() result: 0=stdin, 1=file, 2=not found */

    n = 10;
    a = argstr();
    while (*a == 32) { a = a + 1; }      /* 32 = ' ': skip leading spaces */
    if (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H')) {
        puts("usage: HEAD [-N] [file]   first N lines (default 10), file or stdin");
        return 0;
    }
    if (*a == '-') {                          /* -N : a line count */
        a = a + 1;
        n = 0;
        /* Parse decimal digits (48..57 = '0'..'9'), MSB first: n*10 + digit. */
        while (*a >= 48 && *a <= 57) { n = n * 10 + (*a - 48); a = a + 1; }
        while (*a == 32) { a = a + 1; }       /* skip spaces before the filename */
    }

    /* Point stdin lib at either the named file or the real stdin.
     * openarg() sets up path[]/FOPEN; a==empty means read stdin. */
    fromfile = 0;
    r = openarg(a);
    if (r == 2) { puts("head: not found"); return 1; }
    if (r == 1) { fromfile = 1; }             /* got a file; else fall back to stdin */

    lines = 0;
    /* Copy chars until EOF or we've seen n full lines. A line is counted
     * only when its terminating LF (10) is emitted, so a final unterminated
     * line still prints but does not add to the count. */
    c = nextc();
    while (c != 65535 && lines < n) {
        putchar(c);
        if (c == 10) { lines = lines + 1; }   /* 10 = LF: end of a line */
        c = nextc();
    }
    return 0;
}
