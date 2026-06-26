/* lib_regex.c — shared basic-regex matcher for /BIN commands.
 *
 * Spliced in by `//#use regex` (see README "Shared code"). The classic tiny
 * Thompson/Pike matcher (Kernighan's "Beautiful Code" dialect):
 *   .   any single character
 *   *   zero or more of the preceding character (or '.')
 *   ^   anchor to the start of the line (only meaningful as the first char)
 *   $   anchor to the end   (only meaningful as the last char)
 * everything else is literal. A single self-recursive matchhere() (the `c*`
 * case is an inline loop, NOT a separate matchstar) — deliberately no forward
 * declaration / mutual recursion, since the native p8cc.c bootstrap rejects a
 * standalone prototype. Stays in the p8cc.c subset (no ++/--, decls at top).
 *
 *   matchhere(re, t)  1 if re matches a PREFIX of t; on success sets the global
 *                     `rend` to t advanced past the match (so a caller like sed
 *                     can compute the matched length = rend - start).
 *   match(re, t)      1 if re matches ANYWHERE in t (honours a leading '^').
 *
 * Note: matchstar tries zero repetitions first, so `*` is non-greedy (shortest
 * match) — fine for grep (yes/no) and adequate for sed's s///.
 */
char *rend;                                  /* end of the last successful match */

int matchhere(char *re, char *t) {
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
    if (re[0] == 0) { rend = t; return 1; }              /* whole pattern consumed */
    if (re[0] == '$' && re[1] == 0) {
        if (*t == 0) { rend = t; return 1; }
        return 0;
    }
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
