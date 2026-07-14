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

int abspath(char *out, char *a) {
    int i;
    int j;
    i = 0;
    if (*a != '/') {                          /* relative -> prefix the CWD */
        bios(SYS_GETCWD, out, 0);                 /* SYS_GETCWD -> out */
        while (out[i] != 0) { i = i + 1; }
        if (i > 0 && out[i - 1] != '/') { out[i] = '/'; i = i + 1; }
    }
    j = 0;
    while (a[j] != 0 && a[j] != 13 && a[j] != 32) {
        out[i] = a[j]; i = i + 1; j = j + 1;
    }
    out[i] = 0;
    return j;                                 /* number of chars consumed */
}
