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
 * BIOS: FOPENDIR=$0139, FNEXT=$013C, FSDIRBUF=$0145; OS: SYS_OPENCWD=$2012.
 */
//#use glob     /* gmatch(pat,name) — clib.py splices it above (recursive //#use) */
//#use dirent   /* de_read/de_isfile/de_isdot: current entry via SYS_DIRENTRY */
//#use abi     /* named BIOS/OS addresses: FOPEN, FGETB, SYS_GETCWD, RDBUF, ... */

/* glob_expand — split `pat` into <dir prefix>/<leaf>, open that directory
 * (named dir via FOPENDIR, else the CWD), walk every entry with FNEXT, and for
 * each real FILE whose name matches the leaf glob append "<dir><name>" to `out`.
 *   in:  pat  = pattern; the arg string is terminated by NUL, CR (13) or SP (32)
 *        out  = maxn 64-byte path slots; maxn = slot capacity
 *   out: return = match count (0..maxn); slots filled in directory-scan order
 *   note: BIOS dir iteration (FNEXT) and SYS_DIRENTRY clobber P1/P2 per the ABI,
 *         so no pointer state is held live across the loop's bios() calls.
 */
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
    int lim;
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
        if (slashpos > 62) { return 0; }     /* prefix + NUL must fit dir[64]; a
                                              * longer one names no openable dir */
        ls = slashpos + 1;
        j = 0;
        while (j <= slashpos) { dir[j] = pat[j]; j = j + 1; }
        dir[j] = 0;
    }
    j = 0;                                    /* leaf = pattern after the last '/' */
    /* leaf[16] holds 15 chars + NUL; P8XFS names are 12, so a longer leaf can
     * match nothing anyway — cap it rather than run off the end. */
    while (ls < i && j < 15) { leaf[j] = pat[ls]; j = j + 1; ls = ls + 1; }
    leaf[j] = 0;

    if (hasslash) { bios(FOPENDIR, dir, 0); }  /* FOPENDIR(dir) */
    else { bios(SYS_OPENCWD, 0, 0); }             /* SYS_OPENCWD */
    bios(FSDIRBUF, 0, 0xFA);                   /* FSDIRBUF: iterate on page $FA (high TPA) */

    cnt = 0;
    r = bios(FNEXT, 0, 0);                  /* FNEXT: advance to first entry */
    while ((r & 256) == 0) {                   /* bit 8 (256) set => end of directory */
        de_read();                            /* snapshot the entry (SYS_DIRENTRY) */
        if (de_isdot() == 0 && de_isfile()) {   /* a FILE, not '.'/'..'/dir */
            j = 0;                            /* trim de[] name -> nm */
            c = de[0] & 255;                  /* name is a space-padded 12-byte field; */
            while (j < 12 && c != 32) { nm[j] = c; j = j + 1; c = de[j] & 255; } /* stop at first pad space */
            nm[j] = 0;
            if (gmatch(leaf, nm) && cnt < maxn) {
                base = cnt * 64;              /* out[slot] = dir prefix + name */
                lim = base + 63;              /* a slot is 64 bytes: 63 + NUL */
                j = 0;
                while (dir[j] != 0 && base < lim) { out[base] = dir[j]; base = base + 1; j = j + 1; }
                j = 0;
                while (nm[j] != 0 && base < lim) { out[base] = nm[j]; base = base + 1; j = j + 1; }
                out[base] = 0;
                cnt = cnt + 1;
            }
        }
        r = bios(FNEXT, 0, 0);
    }
    return cnt;
}
