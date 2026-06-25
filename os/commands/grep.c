/* grep.c — print stdin lines matching a basic regular expression. Unix `grep`
 * with a small regex dialect:
 *     .   any single character
 *     *   zero or more of the preceding character (or '.')
 *     ^   anchor to the start of the line   (only special as the first char)
 *     $   anchor to the end of the line     (only special as the last char)
 * everything else is a literal. (No character classes, +, ?, or alternation.)
 *
 *     GREP "be.a" <FILE      -> lines matching be<any>a
 *     GREP "^al"  <FILE      -> lines starting with "al"
 *     GREP "a$"   <FILE      -> lines ending in 'a'
 *     cmd | GREP "x.*y"      -> filter a pipe
 *
 * Reads stdin a line at a time (CR, LF, or CRLF all end a line). The pattern is
 * the first argument word (no spaces). Lines are capped at 127 characters.
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

int main() {
    char *pat;
    char pbuf[64];
    int i;
    int n;
    int c;

    pat = argstr();
    while (*pat == 32) { pat = pat + 1; }
    if (*pat == 0 || *pat == 13 ||
        (*pat == '-' && (*(pat + 1) == 'h' || *(pat + 1) == 'H'))) {
        puts("usage: GREP regex   print stdin lines matching regex (. * ^ $)");
        return 0;
    }
    i = 0;                                    /* copy the first arg word as the pattern */
    while (pat[i] != 0 && pat[i] != 32 && pat[i] != 13 && i < 63) {
        pbuf[i] = pat[i];
        i = i + 1;
    }
    pbuf[i] = 0;

    n = 0;
    c = getchar();
    while (c != 65535) {
        if (c == 10 || c == 13) {             /* end of line */
            line[n] = 0;
            if (n > 0 && match(pbuf, line)) { puts(line); }
            n = 0;
        } else {
            if (n < 127) { line[n] = c; n = n + 1; }
        }
        c = getchar();
    }
    if (n > 0) {                              /* a final line with no trailing newline */
        line[n] = 0;
        if (match(pbuf, line)) { puts(line); }
    }
    return 0;
}
