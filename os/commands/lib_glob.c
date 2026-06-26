/* lib_glob.c — shared filename glob matcher for /BIN commands.
 *
 * Spliced in by `//#use glob` (see README "Shared code"). Whole-string,
 * case-insensitive match of a name against a pattern with the usual wildcards:
 *   *   matches any run of characters (including none)
 *   ?   matches exactly one character
 * any other char matches itself (case-insensitively, since P8XFS names are
 * upper-cased). Returns 1 on a full match, else 0.
 *
 * Self-recursive (no forward decl / mutual recursion) and within the native
 * p8cc.c subset, modelled on grep's matchhere(). Pointer+const args like
 * gmatch(p+1, s) are fine (that's what grep does).
 */
int gmatch(char *p, char *s) {
    int pc;
    int sc;
    if (p[0] == '*') {                       /* '*' = zero or more characters */
        while (1) {
            if (gmatch(p + 1, s)) { return 1; }
            if (*s == 0) { return 0; }
            s = s + 1;
        }
    }
    if (p[0] == 0) { return *s == 0; }       /* both ended together -> match */
    if (*s == 0) { return 0; }
    if (p[0] == '?') { return gmatch(p + 1, s + 1); }
    pc = p[0];
    if (pc >= 'a' && pc <= 'z') { pc = pc - 32; }
    sc = *s;
    if (sc >= 'a' && sc <= 'z') { sc = sc - 32; }
    if (pc == sc) { return gmatch(p + 1, s + 1); }
    return 0;
}
