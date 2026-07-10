/* DEPRECATED (kept for reference, NOT built/shipped): the self-hosted C front
   end (cpp | lex | cc1) is superseded by `cc` (apps/p8xcc.asm), which compiles
   entirely on-target. See os/run.sh and BACKLOG.md. */
/* cpp.c — the //#use source preprocessor: pass 1 of the on-target C toolchain.
 *
 *     CPP src.c >out.c          splice //#use libs, combined source to stdout
 *     CPP src.c | ...           ... or straight into the next pass
 *
 * The native counterpart of host tools/clib.py. A `//#use NAME` directive is
 * replaced with the contents of lib_NAME.c from the SAME directory, recursively
 * (a lib may //#use others), deduped, with each lib's dependencies emitted above
 * it — so the combined source stays inside the p8cc subset (definitions before
 * use, no forward declarations). A source with no //#use passes through.
 *
 * The BIOS has ONE read stream, so cpp never nests file reads. splice(path):
 *   pass 1  read the file, collect its //#use NAMES into a small local list;
 *   emit    for each new name, emit its lib first (splice(), self-recursion —
 *           its own reads happen while THIS file's stream is closed);
 *   pass 2  RE-read the file and emit its lines minus the //#use directives.
 * Only the dependency-name lists live on the stack, so memory stays flat.
 *
 * BIOS: FRESOLVE=$0133 (P1=path), FOPEN=$0124 (P1=buf; C=1 missing),
 * FGETB=$0127 (->A, C=1 at EOF). Read buffer at $FC00.  Within the p8cc subset
 * (no ++/--, no break/continue, decls at top, flat arrays, self-recursion).
 */
//#use apath   /* abspath(out, a): a CWD-relative path word -> absolute */

char dir[64];                     /* directory of the source (lib_*.c live here) */
char line[256];                   /* the current line of the file being scanned */
char inc[160];                    /* names already spliced: 16 slots x 10, deduped */
int  ninc;
int  ateof;                       /* set by rdln() at end of stream */

/* emit: write a NUL-terminated string to stdout (no trailing newline). */
int emit(char *s) {
    int i;
    i = 0;
    while (s[i] != 0) { putchar(s[i]); i = i + 1; }
    return 0;
}

/* openf: FRESOLVE + FOPEN the file at path for reading. Returns 1 if missing. */
int openf(char *path) {
    bios(0x0133, path, 0);                     /* FRESOLVE -> DIRLBA + FNAME */
    if (bios(0x0124, 0xFC00, 0) & 256) { return 1; }   /* FOPEN; C=1 not found */
    return 0;
}

/* rdln: read the next line of the open stream into line[] (keeping the '\n',
 * NUL-terminated). Sets ateof and returns 0 when the stream is exhausted. */
int rdln() {
    int n;
    int c;
    int done;
    n = 0;
    ateof = 0;
    c = bios(0x0127, 0, 0);                    /* FGETB */
    if (c & 256) { ateof = 1; line[0] = 0; return 0; }
    done = 0;
    while (done == 0) {
        if (n < 255) { line[n] = c & 255; n = n + 1; }
        if ((c & 255) == 10) { done = 1; }     /* newline ends the line (kept) */
        else {
            c = bios(0x0127, 0, 0);
            if (c & 256) { done = 1; }          /* EOF mid-line: end here */
        }
    }
    line[n] = 0;
    return n;
}

/* usename: if line[] is a `//#use NAME` directive, copy NAME to out and return
 * 1; else 0. Matches optional leading whitespace, //#use, whitespace, then a C
 * identifier (anything after NAME is ignored). */
int usename(char *out) {
    int i;
    int j;
    i = 0;
    while (line[i] == 32 || line[i] == 9) { i = i + 1; }
    if (line[i] != '/' || line[i + 1] != '/') { return 0; }
    if (line[i + 2] != '#' || line[i + 3] != 'u' ||
        line[i + 4] != 's' || line[i + 5] != 'e') { return 0; }
    i = i + 6;
    if (line[i] != 32 && line[i] != 9) { return 0; }
    while (line[i] == 32 || line[i] == 9) { i = i + 1; }
    j = 0;
    while ((line[i] >= 'A' && line[i] <= 'Z') ||
           (line[i] >= 'a' && line[i] <= 'z') ||
           (line[i] >= '0' && line[i] <= '9') || line[i] == '_') {
        out[j] = line[i]; i = i + 1; j = j + 1;
    }
    out[j] = 0;
    return j != 0;
}

/* seen: 1 if name n is already recorded in inc[] (deduplication). */
int seen(char *n) {
    int i;
    int j;
    i = 0;
    while (i < ninc) {
        j = 0;
        while (inc[i * 10 + j] != 0 && n[j] != 0 && inc[i * 10 + j] == n[j]) {
            j = j + 1;
        }
        if (inc[i * 10 + j] == 0 && n[j] == 0) { return 1; }
        i = i + 1;
    }
    return 0;
}

/* record: add name n to inc[]. */
int record(char *n) {
    int j;
    j = 0;
    while (n[j] != 0 && j < 9) { inc[ninc * 10 + j] = n[j]; j = j + 1; }
    inc[ninc * 10 + j] = 0;
    ninc = ninc + 1;
    return 0;
}

/* buildlib: out <- dir + "/lib_" + name + ".c". */
int buildlib(char *out, char *name) {
    int i;
    int j;
    i = 0;
    j = 0;
    while (dir[j] != 0) { out[i] = dir[j]; i = i + 1; j = j + 1; }
    out[i] = '/'; i = i + 1;
    out[i] = 'l'; i = i + 1;
    out[i] = 'i'; i = i + 1;
    out[i] = 'b'; i = i + 1;
    out[i] = '_'; i = i + 1;
    j = 0;
    while (name[j] != 0) { out[i] = name[j]; i = i + 1; j = j + 1; }
    out[i] = '.'; i = i + 1;
    out[i] = 'c'; i = i + 1;
    out[i] = 0;
    return 0;
}

/* splice: expand path to stdout (see file header). Self-recursive. */
int splice(char *path) {
    char deps[80];                             /* this file's //#use names: 8 x 10 */
    char nm[10];
    char lib[80];
    int  nd;
    int  i;
    int  k;
    int  done;
    nd = 0;
    if (openf(path)) { emit("cpp: cannot open "); emit(path); putchar(10); return 1; }
    done = 0;                                   /* pass 1: collect //#use names */
    while (done == 0) {
        rdln();
        if (ateof) { done = 1; }
        else {
            if (usename(nm)) {
                if (nd < 8) {
                    k = 0;
                    while (nm[k] != 0) { deps[nd * 10 + k] = nm[k]; k = k + 1; }
                    deps[nd * 10 + k] = 0;
                    nd = nd + 1;
                }
            }
        }
    }
    i = 0;                                      /* emit each new dependency first */
    while (i < nd) {
        k = 0;
        while (deps[i * 10 + k] != 0) { nm[k] = deps[i * 10 + k]; k = k + 1; }
        nm[k] = 0;
        if (seen(nm) == 0) {
            record(nm);
            buildlib(lib, nm);
            emit("/* --- cpp: spliced lib_"); emit(nm); emit(".c --- */\n");
            splice(lib);
            emit("/* --- cpp: end lib_"); emit(nm); emit(".c --- */\n");
        }
        i = i + 1;
    }
    openf(path);                                /* pass 2: emit content, minus //#use */
    done = 0;
    while (done == 0) {
        rdln();
        if (ateof) { done = 1; }
        else { if (usename(nm) == 0) { emit(line); } }
    }
    return 0;
}

int main() {
    char *arg;
    char abs[80];
    int i;
    int last;

    arg = argstr();
    while (*arg == 32) { arg = arg + 1; }
    if (*arg == 0 || *arg == 13 ||
        (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H'))) {
        puts("usage: CPP src.c   splice //#use libs; combined source to stdout");
        return 0;
    }

    /* Move the directory-scan buffer (FFIND/FSCAN) off SBUF to page $E000, so
     * opening each source/lib doesn't corrupt the OS's redirected write stream
     * (which keeps its partial output sector in SBUF). $E000 is clear of our
     * code/globals, the $FC00 read buffer, and the C-stack. Same trick as cp -r. */
    bios(0x0145, 0, 0xE0);                      /* FSDIRBUF: scan on page $E000 */

    abspath(abs, arg);                          /* absolute source path */
    last = 0;                                   /* index of its last '/' */
    i = 0;
    while (abs[i] != 0) { if (abs[i] == '/') { last = i; } i = i + 1; }
    i = 0;                                       /* dir = path up to (not incl) it */
    while (i < last) { dir[i] = abs[i]; i = i + 1; }
    dir[i] = 0;

    ninc = 0;
    splice(abs);
    return 0;
}
