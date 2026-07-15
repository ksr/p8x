/* lib_streq.c — shared NUL-terminated string equality for /BIN commands.
 *
 * Spliced in by `//#use streq` (see README "Shared code").
 *   streq(p, q):  1 if the strings are equal (both reach NUL together), else 0.
 *
 * Within the native p8cc.c subset; no dependencies beyond its own locals.
 */
int streq(char *p, char *q) {
    int i;
    i = 0;
    /* Advance while chars match AND we haven't hit p's NUL. Loop stops at the
     * first differing byte, or when p[i]==0. The final compare then decides:
     * if both are NUL the strings matched to the end (equal); if only one is
     * NUL, or they differ mid-string, p[i]!=q[i] so we return 0. */
    while (p[i] != 0 && p[i] == q[i]) { i = i + 1; }
    return p[i] == q[i];                       /* both reached NUL together */
}
