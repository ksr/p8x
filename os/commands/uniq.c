/* uniq.c — collapse adjacent duplicate lines (Unix `uniq`).
 *
 *     UNIQ file            file with adjacent dup lines collapsed
 *     SORT f | UNIQ        the usual pairing (uniq only sees *adjacent* dups)
 *
 * Reads a named file (opened like cat) or stdin. Prints a line only when it
 * differs from the previous printed line. Lines capped at 128 chars.
 */
//#use stdin   /* path[80], fromfile, nextc(), openarg() */
char cur[130];
char prev[130];

int readline(char *buf) {                     /* 1 if a line read, 0 at EOF */
    int n;
    int c;
    n = 0;
    c = nextc();
    if (c == 65535) { return 0; }
    while (c != 65535 && c != 10) {
        if (c != 13 && n < 128) { buf[n] = c; n = n + 1; }
        c = nextc();
    }
    buf[n] = 0;
    return 1;
}

int streq(char *p, char *q) {
    int i;
    i = 0;
    while (p[i] != 0 && p[i] == q[i]) { i = i + 1; }
    return p[i] == q[i];
}

int main() {
    char *a;
    int r;
    int first;
    int i;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H')) {
        puts("usage: UNIQ [file]   collapse adjacent duplicate lines");
        return 0;
    }
    fromfile = 0;
    r = openarg(a);
    if (r == 2) { puts("uniq: not found"); return 1; }
    if (r == 1) { fromfile = 1; }

    first = 1;
    while (readline(cur)) {
        if (first || streq(cur, prev) == 0) { puts(cur); }
        i = 0;                                /* prev = cur */
        while (cur[i] != 0) { prev[i] = cur[i]; i = i + 1; }
        prev[i] = 0;
        first = 0;
    }
    return 0;
}
