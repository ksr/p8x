/* lib_regex.c — shared basic-regex matcher for /BIN commands (grep, sed).
 *
 * Spliced in by `//#use regex` (see README "Shared code"). The classic tiny
 * Thompson/Pike matcher (Kernighan's "Beautiful Code" dialect) with the two
 * cheap single-character quantifiers added:
 *   .   any single character
 *   *   zero or more of the preceding character (or '.')
 *   +   one  or more of the preceding character (or '.')
 *   ?   zero or one  of the preceding character (or '.')
 *   ^   anchor to the start of the line (only meaningful as the first char)
 *   $   anchor to the end   (only meaningful as the last char)
 * everything else is literal. One self-recursive matchhere() — deliberately no
 * forward declaration / mutual recursion, since the native p8cc.c bootstrap
 * rejects a standalone prototype. Stays in the p8cc.c subset (no ++/--, decls
 * at top). (Character classes [..] and \ escapes don't fit in grep's host build
 * yet — blocked on the p8cc codegen-size work; see BACKLOG.)
 *
 *   matchhere(re, t)  1 if re matches a PREFIX of t; on success sets the global
 *                     `rend` to t advanced past the match (so a caller like sed
 *                     can compute the matched length = rend - start).
 *   match(re, t)      1 if re matches ANYWHERE in t (honours a leading '^').
 *
 * Quantifiers are non-greedy (try fewest first) — fine for grep (yes/no) and
 * adequate for sed's s///.
 */
char *rend;                                  /* end of the last successful match */

/* matchhere: does regex `re` match a PREFIX of text `t`?
 *   re, t : NUL-terminated pattern and remaining input, both scanned in place.
 *   returns 1 on match (and sets global `rend` to t past the matched prefix),
 *           0 otherwise (`rend` left unchanged).
 * Quantifier cases are tested before the plain literal case because a '*'/'+'/'?'
 * in re[1] rebinds the meaning of the char in re[0]. Recurses on the tail. */
int matchhere(char *re, char *t) {
    int c;
    c = re[0] & 255;
    if (c != 0 && re[1] == '*') {            /* c* then re[2..] : zero or more */
        while (1) {
            if (matchhere(re + 2, t)) { return 1; }
            if (*t == 0) { return 0; }
            if (*t != c && c != '.') { return 0; }
            t = t + 1;
        }
    }
    if (c != 0 && re[1] == '+') {             /* c+ : one or more */
        if (*t == 0 || (*t != c && c != '.')) { return 0; }
        t = t + 1;
        while (1) {
            if (matchhere(re + 2, t)) { return 1; }
            if (*t == 0) { return 0; }
            if (*t != c && c != '.') { return 0; }
            t = t + 1;
        }
    }
    if (c != 0 && re[1] == '?') {             /* c? : zero or one */
        if (*t != 0 && (*t == c || c == '.')) {
            if (matchhere(re + 2, t + 1)) { return 1; }
        }
        return matchhere(re + 2, t);
    }
    if (re[0] == 0) { rend = t; return 1; }              /* whole pattern consumed */
    /* '$' is an end-of-line anchor only as the final pattern char; matches the
     * NUL terminator without consuming any input. A '$' elsewhere falls through
     * to the literal case below and matches a real '$' byte. */
    if (re[0] == '$' && re[1] == 0) {
        if (*t == 0) { rend = t; return 1; }
        return 0;
    }
    if (*t != 0 && (re[0] == '.' || re[0] == *t)) {
        return matchhere(re + 1, t + 1);
    }
    return 0;
}

/* match: does `re` match anywhere in `t`? Returns 1/0; on success `rend` (set by
 * matchhere) points just past the match, so sed can measure the matched span.
 * A leading '^' anchors to start, so it only tries position 0; otherwise it
 * walks each starting offset until a match or the end of the string. */
int match(char *re, char *t) {               /* 1 if re matches anywhere in t */
    if (re[0] == '^') { return matchhere(re + 1, t); }
    while (1) {                              /* try each starting position */
        if (matchhere(re, t)) { return 1; }
        if (*t == 0) { return 0; }
        t = t + 1;
    }
}
