/* sed.c — stream substitution: the `s/old/new/[g]` command (Unix `sed`).
 *
 *     SED s/foo/bar/ file      replace the first "foo" on each line with "bar"
 *     SED s/foo/bar/g file     replace every "foo"
 *     cmd | SED s/x/y/         substitute on a pipe
 *
 * Only the `s///` command. The left-hand side is a **basic regex** (`.` `*` `^`
 * `$`, via the shared lib_regex — same matcher as grep); the replacement is
 * literal. Reads a named file (opened like cat) or stdin; on each line, replaces
 * the first match (or all with `g`) and prints the result. The matched span (not
 * a fixed length) is what gets replaced. `*` is non-greedy (shortest match);
 * a zero-length match is skipped. Lines capped at 128 chars, output at 255.
 */
//#use stdin   /* path[80], fromfile, nextc(), openarg() */
char pat[64];
char rep[64];
char line[260];
char out[260];
int  anchored;                                /* 1 = pattern began with '^' */
char *rpat;                                   /* pattern to match (past any '^') */

//#use readline
//#use regex   /* match/matchhere (. * ^ $) + rend, shared with grep */

/* re_at: length of the regex match starting at line[i], or 0 if none here.
 * matchhere() sets rend past the match; a zero-length match counts as "no
 * match" so a star pattern can't loop forever. A leading '^' anchors to i==0. */
int re_at(int i) {
    char *lp;
    char *q;
    int len;
    if (anchored && i != 0) { return 0; }
    lp = line + i;
    if (matchhere(rpat, lp) == 0) { return 0; }
    len = 0;
    q = lp;
    while (q != rend) { q = q + 1; len = len + 1; }
    return len;
}

int main() {
    char *a;
    int r;
    int global;
    int mlen;
    int i;
    int j;
    int n;
    int done;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: SED s/re/new/[g] [file]   substitute (regex: . * ^ $)");
        return 0;
    }
    if (a[0] != 's' || a[1] != '/') { puts("sed: only s/re/new/[g]"); return 1; }
    a = a + 2;
    i = 0;                                     /* pattern up to '/' */
    while (*a != 0 && *a != '/' && i < 63) { pat[i] = *a; i = i + 1; a = a + 1; }
    pat[i] = 0;
    anchored = 0;
    rpat = pat;
    if (pat[0] == '^') { anchored = 1; rpat = pat + 1; }   /* ^ anchors to start */
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
            mlen = 0;
            if (global || done == 0) { mlen = re_at(i); }   /* regex match here? */
            if (mlen > 0) {
                j = 0;
                while (rep[j] != 0 && n < 255) { out[n] = rep[j]; n = n + 1; j = j + 1; }
                i = i + mlen;                  /* skip the whole matched span */
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
