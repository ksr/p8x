/* grep.c — print stdin lines matching a basic regular expression. Unix `grep`
 * with a small regex dialect:
 *     .   any single character
 *     *   zero or more of the preceding character (or '.')
 *     ^   anchor to the start of the line   (only special as the first char)
 *     $   anchor to the end of the line     (only special as the last char)
 * everything else is a literal. (No character classes, +, ?, or alternation.)
 *
 *     GREP "^al" FILE        -> lines of FILE starting with "al"
 *     GREP "be.a" <FILE      -> from stdin (a redirect): be<any>a
 *     cmd | GREP "x.*y"      -> filter a pipe
 *
 * Like cat, grep reads a **named file** if a second argument is given, otherwise
 * **stdin** (so `<`/`|` still work). The file is opened the same way cat does:
 * an absolute path (CWD via SYS_GETCWD unless already absolute), FRESOLVE +
 * FOPEN, with the read buffer at $FC00. Reads a line at a time (CR, LF, or CRLF
 * all end a line). The regex is the first argument word (no spaces); lines are
 * capped at 127 characters.
 *
 * --- match(): the classic tiny regex matcher (Thompson/Pike style) -----------
 * Self-contained and dependency-free, so it can be copied verbatim into any
 * other command that wants basic patterns (there is no linker / #include here;
 * see os/commands/README "shared code"). Written with a single self-recursive
 * matchhere() — the `c*` case is an inline loop rather than a separate
 * matchstar() — so it needs no forward declaration / mutual recursion (which the
 * native p8cc.c bootstrap doesn't accept). Both p8cc.py and p8cc.c compile it.
 */
char line[128];                              /* the current input line */

int matchhere(char *re, char *t) {           /* match re at the start of t */
    int c;
    if (re[0] != 0 && re[1] == '*') {        /* re[0]* then re[2..] */
        c = re[0];
        while (1) {
            if (matchhere(re + 2, t)) { return 1; }   /* zero or more c */
            if (*t == 0) { return 0; }
            if (*t != c && c != '.') { return 0; }
            t = t + 1;
        }
    }
    if (re[0] == 0) { return 1; }
    if (re[0] == '$' && re[1] == 0) { return *t == 0; }
    if (*t != 0 && (re[0] == '.' || re[0] == *t)) {
        return matchhere(re + 1, t + 1);
    }
    return 0;
}
int match(char *re, char *t) {               /* 1 if re matches anywhere in t */
    if (re[0] == '^') { return matchhere(re + 1, t); }
    while (1) {                              /* try each starting position */
        if (matchhere(re, t)) { return 1; }
        if (*t == 0) { return 0; }
        t = t + 1;
    }
}

//#use stdin   /* path[80], fromfile, nextc(), openarg() */

int main() {
    char *a;
    char pbuf[64];
    int i;
    int j;
    int n;
    int c;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: GREP regex [file]   match regex (. * ^ $) in file or stdin");
        return 0;
    }
    i = 0;                                    /* the regex = the first arg word */
    while (a[i] != 0 && a[i] != 32 && a[i] != 13 && i < 63) {
        pbuf[i] = a[i];
        i = i + 1;
    }
    pbuf[i] = 0;
    a = a + i;                                /* skip to a possible second word: a file */
    while (*a == 32) { a = a + 1; }

    fromfile = 0;
    j = openarg(a);                           /* open the optional file arg, else stdin */
    if (j == 2) { puts("grep: not found"); return 1; }
    if (j == 1) { fromfile = 1; }

    n = 0;
    c = nextc();
    while (c != 65535) {
        if (c == 10 || c == 13) {             /* end of line */
            line[n] = 0;
            if (n > 0 && match(pbuf, line)) { puts(line); }
            n = 0;
        } else {
            if (n < 127) { line[n] = c; n = n + 1; }
        }
        c = nextc();
    }
    if (n > 0) {                              /* a final line with no trailing newline */
        line[n] = 0;
        if (match(pbuf, line)) { puts(line); }
    }
    return 0;
}
