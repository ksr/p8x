/* uniq.c — collapse adjacent duplicate lines (Unix `uniq`).
 *
 *     UNIQ file            file with adjacent dup lines collapsed
 *     SORT f | UNIQ        the usual pairing (uniq only sees *adjacent* dups)
 *
 * Reads a named file (opened like cat) or stdin. Prints a line only when it
 * differs from the previous printed line. Lines capped at 128 chars.
 */
char path[80];
int fromfile;
char cur[130];
char prev[130];

int nextc() {
    int c;
    if (fromfile) {
        c = bios(0x0127, 0, 0);
        if (c & 256) { return 65535; }
        return c & 255;
    }
    return getchar();
}

int openarg(char *a) {                        /* 0=stdin, 1=opened, 2=not found */
    int i;
    int j;
    if (*a == 0 || *a == 13) { return 0; }
    i = 0;
    if (*a != '/') {
        bios(0x4003, path, 0);
        while (path[i] != 0) { i = i + 1; }
        if (i > 0 && path[i - 1] != '/') { path[i] = '/'; i = i + 1; }
    }
    j = 0;
    while (a[j] != 0 && a[j] != 13 && a[j] != 32) {
        path[i] = a[j]; i = i + 1; j = j + 1;
    }
    path[i] = 0;
    bios(0x0133, path, 0);
    if (bios(0x0124, 0xE000, 0) & 256) { return 2; }
    return 1;
}

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
