/* sed.c — stream substitution: the `s/old/new/[g]` command (Unix `sed`).
 *
 *     SED s/foo/bar/ file      replace the first "foo" on each line with "bar"
 *     SED s/foo/bar/g file     replace every "foo"
 *     cmd | SED s/x/y/         substitute on a pipe
 *
 * Only the `s///` command, with **literal** (non-regex) patterns. Reads a named
 * file (opened like cat) or stdin; on each line, replaces occurrences of the
 * pattern with the replacement (first only, or all with the `g` flag) and prints
 * the result. Lines capped at 128 chars; the rewritten line is capped at 255.
 */
//#use stdin   /* path[80], fromfile, nextc(), openarg() */
char pat[64];
char rep[64];
char line[130];
char out[260];

int readline(char *buf) {
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

int matchat(char *s, int i, char *p) {        /* literal: does p occur at s[i]? */
    int k;
    k = 0;
    while (p[k] != 0) {
        if (s[i + k] != p[k]) { return 0; }
        k = k + 1;
    }
    return 1;
}

int main() {
    char *a;
    int r;
    int global;
    int plen;
    int i;
    int j;
    int n;
    int done;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: SED s/old/new/[g] [file]   literal substitution");
        return 0;
    }
    if (a[0] != 's' || a[1] != '/') { puts("sed: only s/old/new/[g]"); return 1; }
    a = a + 2;
    i = 0;                                     /* pattern up to '/' */
    while (*a != 0 && *a != '/' && i < 63) { pat[i] = *a; i = i + 1; a = a + 1; }
    pat[i] = 0;
    plen = i;
    if (*a != '/') { puts("sed: bad s/// (no second /)"); return 1; }
    a = a + 1;
    j = 0;                                     /* replacement up to '/' */
    while (*a != 0 && *a != '/' && j < 63) { rep[j] = *a; j = j + 1; a = a + 1; }
    rep[j] = 0;
    global = 0;
    if (*a == '/') {
        a = a + 1;
        if (*a == 'g' || *a == 'G') { global = 1; a = a + 1; }
    }
    while (*a == 32) { a = a + 1; }            /* optional file */
    fromfile = 0;
    r = openarg(a);
    if (r == 2) { puts("sed: not found"); return 1; }
    if (r == 1) { fromfile = 1; }

    while (readline(line)) {
        n = 0;
        i = 0;
        done = 0;
        while (line[i] != 0) {
            if (plen > 0 && (global || done == 0) && matchat(line, i, pat)) {
                j = 0;
                while (rep[j] != 0 && n < 255) { out[n] = rep[j]; n = n + 1; j = j + 1; }
                i = i + plen;
                if (global == 0) { done = 1; }
            } else {
                if (n < 255) { out[n] = line[i]; n = n + 1; }
                i = i + 1;
            }
        }
        out[n] = 0;
        puts(out);
    }
    return 0;
}
