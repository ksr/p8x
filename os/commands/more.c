/* more.c — page a file (or stdin) a screenful at a time. Unix `more`.
 *
 *     MORE file            page through file
 *     cmd | MORE           page a pipe
 *
 * Prints up to PAGE lines, then "--More--" and waits for a console key:
 *     space   next full page
 *     Enter   one more line
 *     q / Q   quit
 *     other   next full page
 * Content comes from a named file (opened like cat) or stdin; the paging key is
 * always read from the **console** via the BIOS CONIN ($0100), which is separate
 * from the (possibly redirected) stdin stream — so `MORE file` and `cmd | MORE`
 * both pause correctly. This is a forward pager (`more`); it does not scroll
 * back the way full `less` does.
 */
//#use stdin   /* path[80], fromfile, nextc(), openarg() */

int prompt() {                                /* show --More--, erase, return key */
    char *m;
    int k;
    m = "--More--";
    while (*m != 0) { putchar(*m); m = m + 1; }
    k = bios(0x0100, 0, 0) & 255;             /* CONIN: a console key */
    m = "\r        \r";                       /* erase the prompt (8 spaces) */
    while (*m != 0) { putchar(*m); m = m + 1; }
    return k;
}

int main() {
    char *a;
    int c;
    int lines;
    int k;
    int r;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H')) {
        puts("usage: MORE [file]   page a file or stdin (space=next, Enter=line, q=quit)");
        return 0;
    }

    fromfile = 0;
    r = openarg(a);
    if (r == 2) { puts("more: not found"); return 1; }
    if (r == 1) { fromfile = 1; }

    lines = 0;
    c = nextc();
    while (c != 65535) {
        putchar(c);
        if (c == 10) {
            lines = lines + 1;
            if (lines >= 23) {
                k = prompt();
                if (k == 'q' || k == 'Q') { return 0; }
                if (k == 13) { lines = 22; }  /* Enter -> just one more line */
                else { lines = 0; }           /* space/other -> a full page */
            }
        }
        c = nextc();
    }
    return 0;
}
