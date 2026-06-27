/* grep.c — print lines matching a basic regular expression. Unix `grep`
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
 *     GREP *.LOG glob        -> any *|? file arg reads all matches as one stream
 *     GREP -r "x.*y"         -> recurse the CWD tree, search file CONTENTS,
 *                              printing matches as "path:line" (like grep -r)
 *
 * Without -r, grep reads a named file/glob (like cat) or stdin (so `<`/`|`
 * work); read buffer at $FC00. With -r it walks the CWD tree depth-first
 * (FNEXT, same shape as DIR -R / FIND), collects every file's path, then greps
 * each — the walk and the per-file reads are kept in separate phases because the
 * FNEXT cursor is global BIOS state (opening a file mid-walk would clobber it).
 * Lines are capped at 255 chars; the recursive search is capped at 48 files.
 *
 * The basic-regex matcher (`match`/`matchhere`) lives in the shared lib_regex.c
 * (`//#use regex`); sed uses the same library.
 */
char line[256];                              /* the current input line */
char cur[256];                               /* -r: path of the directory being walked */
char nm[16];                                 /* -r: current entry name (trimmed) */
char rfiles[4608];                           /* -r: collected file paths, 48 x 96 */
int  nrf;                                    /* -r: number of paths collected */
char re[64];                                 /* the compiled regex (first arg word) */

//#use regex   /* match(re,t)/matchhere(re,t): the basic-regex matcher . * ^ $ */
//#use stdin   /* path[80], fromfile, nextc(), openarg(), open_path() */

/* grep_stream: read the currently-open input (file stream or stdin) line by
 * line and print each match. If pfx != 0, print "pfx:" before the line (for -r).
 */
int grep_stream(char *pfx) {
    int n;
    int c;
    int i;
    n = 0;
    c = nextc();
    while (c != 65535) {
        if (c == 10 || c == 13) {             /* end of line */
            line[n] = 0;
            if (n > 0 && match(re, line)) {
                if (pfx != 0) {
                    i = 0;
                    while (pfx[i] != 0) { putchar(pfx[i]); i = i + 1; }
                    putchar(':');
                }
                puts(line);
            }
            n = 0;
        } else {
            if (n < 255) { line[n] = c; n = n + 1; }
        }
        c = nextc();
    }
    if (n > 0) {                              /* a final line with no trailing newline */
        line[n] = 0;
        if (match(re, line)) {
            if (pfx != 0) {
                i = 0;
                while (pfx[i] != 0) { putchar(pfx[i]); i = i + 1; }
                putchar(':');
            }
            puts(line);
        }
    }
    return 0;
}

int rdname() {                               /* FNAME ($704A, 12 space-padded) -> nm */
    int i;
    int k;
    int c;
    k = 0;
    i = 0;
    while (i < 12) {
        c = peek(0x704A + i) & 255;
        if (c != 32) { nm[k] = c; k = k + 1; }
        i = i + 1;
    }
    nm[k] = 0;
    return k;
}

/* collect: walk the directory whose iteration is already open, appending each
 * FILE's full path (cur + '/' + name) to rfiles[], then descend into subdirs.
 * Same recursion shape as FIND/DIR -R; plen = length of cur (no trailing /). */
int collect(int plen) {
    int clba[24];                            /* child subdir start LBAs, this level */
    char cn[384];                            /* 24 child names x 16 */
    int nsub;
    int r;
    int i;
    int k;
    int oldp;
    int base;

    nsub = 0;
    r = bios(0x013C, 0, 0);                  /* FNEXT */
    while ((r & 256) == 0) {
        if (peek(0x704A) != '.') {           /* skip '.' / '..' */
            rdname();
            if (peek(0x7070) == 1 && nrf < 48) {   /* a FILE -> record its path */
                base = nrf * 96;
                i = 0;
                while (i < plen) { rfiles[base] = cur[i]; base = base + 1; i = i + 1; }
                if (plen != 1 || cur[0] != '/') { rfiles[base] = '/'; base = base + 1; }
                k = 0;
                while (nm[k] != 0) { rfiles[base] = nm[k]; base = base + 1; k = k + 1; }
                rfiles[base] = 0;
                nrf = nrf + 1;
            }
            if (peek(0x7070) == 2 && nsub < 24) {  /* a subdirectory -> descend later */
                clba[nsub] = peek(0x7047) + peek(0x7048) * 256;
                k = 0;
                while (nm[k] != 0) { cn[nsub * 16 + k] = nm[k]; k = k + 1; }
                cn[nsub * 16 + k] = 0;
                nsub = nsub + 1;
            }
        }
        r = bios(0x013C, 0, 0);
    }

    i = 0;                                    /* descend into each recorded child */
    while (i < nsub) {
        poke(0x7048, clba[i] / 256);         /* FOPENDIRAT high byte (LBA1) */
        poke(0x7049, 0);
        bios(0x0142, 0, clba[i]);            /* FOPENDIRAT(child): A=low, LBA1=high */
        bios(0x0145, 0, 0xEA);               /* FSDIRBUF: our page */
        oldp = plen;
        if (plen != 1 || cur[0] != '/') { cur[plen] = '/'; plen = plen + 1; }
        k = 0;
        while (cn[i * 16 + k] != 0) { cur[plen] = cn[i * 16 + k]; plen = plen + 1; k = k + 1; }
        cur[plen] = 0;
        collect(plen);
        cur[oldp] = 0;                       /* restore the prefix */
        plen = oldp;
        i = i + 1;
    }
    return 0;
}

int main() {
    char *a;
    char *p;
    int i;
    int j;
    int recurse;
    int plen;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: GREP [-r] regex [file|glob]   match regex (. * ^ $); -r walks the CWD tree");
        return 0;
    }
    recurse = 0;
    if (*a == '-' && *(a + 1) == 'r') {       /* -r : recursive content search */
        recurse = 1;
        a = a + 2;
        while (*a == 32) { a = a + 1; }
    }
    i = 0;                                    /* the regex = the first arg word */
    while (a[i] != 0 && a[i] != 32 && a[i] != 13 && i < 63) {
        re[i] = a[i];
        i = i + 1;
    }
    re[i] = 0;
    a = a + i;
    while (*a == 32) { a = a + 1; }

    if (recurse) {                            /* walk the CWD tree, grep each file */
        nrf = 0;
        bios(0x4003, cur, 0);                 /* cur = CWD path */
        plen = 0;
        while (cur[plen] != 0) { plen = plen + 1; }
        bios(0x4012, 0, 0);                   /* SYS_OPENCWD: iterate the CWD */
        bios(0x0145, 0, 0xEA);
        collect(plen);                        /* phase 1: gather file paths */
        i = 0;                                /* phase 2: grep each (paths are absolute) */
        while (i < nrf) {
            p = rfiles + i * 96;              /* pointer var, not array+expr as a call arg */
            fromfile = 0;
            if (open_path(p) == 1) { fromfile = 1; grep_stream(p); }
            i = i + 1;
        }
        return 0;
    }

    fromfile = 0;
    j = openarg(a);                           /* the optional file/glob arg, else stdin */
    if (j == 2) { puts("grep: not found"); return 1; }
    if (j == 1) { fromfile = 1; }
    grep_stream(0);                           /* no path prefix in non-recursive mode */
    return 0;
}
