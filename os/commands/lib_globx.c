/* lib_globx.c — expand a filename glob into a list of matching paths.
 *
 * Spliced in by `//#use globx` (see README "Shared code"). For multi-file
 * commands (`cat *.asm`, and later wc/grep/sort): given a pattern whose last
 * component may contain `*`/`?`, scan the directory it names (or the CWD) and
 * collect the FILES (not subdirectories) whose name matches, as a list of paths
 * ready to open.
 *
 *   glob_expand(pat, out, maxn) -> count
 *     pat   the glob, e.g. "*.ASM" (CWD) or "/BIN/*.BIN" (a named directory)
 *     out   caller buffer of maxn fixed 64-byte slots; out[i*64] = the i-th path
 *           (the pattern's directory prefix + the matched name, so it opens the
 *           same way the bare argument would: relative names resolve in the CWD)
 *     maxn  capacity in slots; extra matches past maxn are dropped
 *     ->    number of matches written (0..maxn)
 *
 * DEPENDS on lib_glob's gmatch(): `//#use glob` must appear ABOVE `//#use globx`.
 * Uses FNEXT iteration on page $FA — a 512-byte scratch sector just below the
 * file read buffer ($FC00) and clear of the code/globals below it. (The earlier
 * $E8 page sat INSIDE the program image once cat+globx grew to ~17KB, which
 * scribbled over our own code; the only safe scratch is high in the TPA, above
 * the code end and below the stack at $FE00.) glob_expand finishes building the
 * path list before any file is opened, so sharing the high TPA with the $FC00
 * read buffer is fine — the two are never live at the same instant. Within the
 * p8cc.c subset. NOT pulled into dir/find (they only //#use glob), so it doesn't
 * bloat those size-tight recursive commands.
 *
 * BIOS: FOPENDIR=$0139, FNEXT=$013C, FSDIRBUF=$0145; OS: SYS_OPENCWD=$4012.
 */
//#use glob   /* gmatch(pat,name) — clib.py splices it above (recursive //#use) */
int glob_expand(char *pat, char *out, int maxn) {
    char leaf[16];                           /* the pattern's last component */
    char dir[64];                            /* its directory prefix (incl trailing /) */
    char nm[16];                             /* current entry name (trimmed) */
    int hasslash;
    int slashpos;
    int i;
    int j;
    int ls;
    int cnt;
    int base;
    int c;
    int r;

    hasslash = 0; slashpos = 0; i = 0;
    while (pat[i] != 0 && pat[i] != 13 && pat[i] != 32) {
        if (pat[i] == '/') { hasslash = 1; slashpos = i; }
        i = i + 1;
    }
    ls = 0;
    dir[0] = 0;
    if (hasslash) {                          /* prefix = pat[0..slashpos] incl '/' */
        ls = slashpos + 1;
        j = 0;
        while (j <= slashpos) { dir[j] = pat[j]; j = j + 1; }
        dir[j] = 0;
    }
    j = 0;                                    /* leaf = pattern after the last '/' */
    while (ls < i) { leaf[j] = pat[ls]; j = j + 1; ls = ls + 1; }
    leaf[j] = 0;

    if (hasslash) { bios(0x0139, dir, 0); }  /* FOPENDIR(dir) */
    else { bios(0x4012, 0, 0); }             /* SYS_OPENCWD */
    bios(0x0145, 0, 0xFA);                   /* FSDIRBUF: iterate on page $FA (high TPA) */

    cnt = 0;
    r = bios(0x013C, 0, 0);                  /* FNEXT */
    while ((r & 256) == 0) {
        if (peek(0x704A) != '.' && peek(0x7070) == 1) {   /* a FILE, not '.'/'..'/dir */
            j = 0;                            /* trim FNAME -> nm */
            c = peek(0x704A);
            while (j < 12 && c != 32) { nm[j] = c; j = j + 1; c = peek(0x704A + j); }
            nm[j] = 0;
            if (gmatch(leaf, nm) && cnt < maxn) {
                base = cnt * 64;              /* out[slot] = dir prefix + name */
                j = 0;
                while (dir[j] != 0) { out[base] = dir[j]; base = base + 1; j = j + 1; }
                j = 0;
                while (nm[j] != 0) { out[base] = nm[j]; base = base + 1; j = j + 1; }
                out[base] = 0;
                cnt = cnt + 1;
            }
        }
        r = bios(0x013C, 0, 0);
    }
    return cnt;
}
