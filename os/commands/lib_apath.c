/* lib_apath.c — shared "build an absolute path" helper for /BIN commands.
 * (Named lib_apath.c so it fits P8XFS's 12-char filename field; it defines the
 *  abspath() helper — the `//#use apath` token names the FILE, not the function.)
 *
 * Spliced in by `//#use apath` (see README "Shared code"). Turns a command-line
 * path word into an absolute path the BIOS FRESOLVE can use, prefixing the CWD
 * (SYS_GETCWD $2003) when the word is relative. Unlike lib_stdin's openarg(),
 * this only *builds the string* into a caller-supplied buffer (it does not open
 * anything) — so a command can build two paths (src + dst) into separate buffers.
 *
 *   abspath(out, a):  out <- absolute path of the path word `a`; returns the
 *                     number of chars consumed from `a` (stops at NUL/CR/space).
 *
 * Within the native p8cc.c subset (no ++/--, decls at top). No dependencies
 * beyond the bios() builtin.
 */
//#use abi     /* named BIOS/OS addresses: FOPEN, FGETB, SYS_GETCWD, RDBUF, ... */

/* abspath(out, a) — build an absolute path string.
 *   in:  a   = path word from the command line (arg buffer); scanning stops
 *              at NUL, CR (13), or space (32), so a whole argv line can be
 *              passed and only the first word is consumed.
 *        out = caller-supplied destination buffer (must be large enough to
 *              hold CWD + '/' + the path word + NUL; no bounds check here).
 *   out: writes a NUL-terminated absolute path into *out.
 *   ret: count of chars consumed from `a` (its word length), so the caller
 *        can advance past this word to parse the next one.
 * If `a` is already absolute (leads with '/') it is copied verbatim; else the
 * current working directory is prepended, with a '/' separator inserted unless
 * the CWD already ends in one (handles the root "/" CWD without doubling).
 * Clobbers: whatever SYS_GETCWD clobbers; the syscall also fills *out.
 */
int abspath(char *out, char *a) {
    int i;                                    /* write index into out         */
    int j;                                    /* read index into a            */
    i = 0;
    if (*a != '/') {                          /* relative -> prefix the CWD */
        bios(SYS_GETCWD, out, 0);                 /* SYS_GETCWD -> out */
        while (out[i] != 0) { i = i + 1; }
        if (i > 0 && out[i - 1] != '/') { out[i] = '/'; i = i + 1; }
    }
    j = 0;
    /* Append the path word: copy until NUL, CR (13), or space (32) ends it. */
    while (a[j] != 0 && a[j] != 13 && a[j] != 32) {
        out[i] = a[j]; i = i + 1; j = j + 1;
    }
    out[i] = 0;
    return j;                                 /* number of chars consumed */
}
