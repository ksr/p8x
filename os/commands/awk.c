/* awk.c — a small awk: field-oriented text processing.
 *
 *     awk [-F c] 'program' [file]
 *
 * program is  [/regex/] { print items }  with these pieces:
 *   pattern    /regex/  (basic regex . * + ? ^ $, via lib_regex) or empty = every
 *              line. A bare pattern with no action prints the whole line.
 *   action     { print items } or empty = print the whole line ($0).
 *   items      comma-separated: $0 (whole line), $1..$NF (fields), NF, NR, and
 *              "string literals". Commas print a space between items.
 * Fields split on whitespace by default, or on the single character after -F.
 * Input is a file argument, else stdin (so `cat f | awk '{print $2}'` works).
 *
 * The program is one quoted argument (single or double quotes); awk strips the
 * quotes itself since the shell does not. This is a deliberately small subset
 * (one rule, print only) covering the common `awk '{print $N}'` / `awk /re/`
 * uses; BEGIN/END, printf, and expressions are not yet supported.
 */
//#use stdin   /* nextc(), openarg(), path[], fromfile — file/stdin input */
//#use regex   /* match(re, t): basic-regex matcher . * + ? ^ $ */

char line[256];                              /* the current record ($0), NUL-term */
int  fstart[40];                             /* field start offsets into line[] */
int  flen[40];                               /* field lengths */
int  nf;                                     /* number of fields (NF) */
int  nr;                                     /* record number (NR) */
int  sepc;                                   /* field separator char, 0 = whitespace */
char re[80];                                 /* regex pattern; hasre gates it */
int  hasre;
char act[120];                              /* action body text (inside { }) */

/* readrec: read the next record into line[] (strip CR/LF). 1 = got one, 0 = EOF.
 * nextc() returns 65535 (0xFFFF, an all-ones int) as its EOF sentinel; 10 is LF,
 * 13 is CR. Input past 255 chars is silently truncated to fit line[256] (+NUL). */
int readrec() {
    int c;
    int i;
    c = nextc();
    if (c == 65535) { return 0; }   /* EOF on the very first read -> no record */
    i = 0;
    while (c != 65535 && c != 10) {
        if (c != 13) { if (i < 255) { line[i] = c; i = i + 1; } }
        c = nextc();
    }
    line[i] = 0;
    return 1;
}

/* split: fill fstart/flen/nf from line[] using sepc (0 = whitespace).
 * Two modes: whitespace (space=32/tab=9, collapses runs, skips leading/trailing
 * gaps like real awk) or a single separator char (adjacent seps yield empty
 * fields, awk -F style). Stores field spans as offset+length into line[] rather
 * than copying. Caps at 40 fields (the fstart[]/flen[] size); extra ones drop. */
int split() {
    int i;
    int n;
    int st;
    int done;
    n = 0;
    i = 0;
    if (sepc == 0) {
        while (line[i] != 0) {
            while (line[i] == 32 || line[i] == 9) { i = i + 1; }
            if (line[i] != 0) {
                st = i;
                while (line[i] != 0 && line[i] != 32 && line[i] != 9) { i = i + 1; }
                if (n < 40) { fstart[n] = st; flen[n] = i - st; n = n + 1; }
            }
        }
    } else {
        st = 0;
        i = 0;
        done = 0;
        while (done == 0) {
            if (line[i] == 0) {
                if (n < 40) { fstart[n] = st; flen[n] = i - st; n = n + 1; }
                done = 1;
            } else {
                if (line[i] == sepc) {
                    if (n < 40) { fstart[n] = st; flen[n] = i - st; n = n + 1; }
                    st = i + 1;
                }
                i = i + 1;
            }
        }
    }
    nf = n;
    return n;
}

/* pfield: print $fi (0 = the whole record, 1..nf = a field). */
int pfield(int fi) {
    int i;
    if (fi == 0) {
        i = 0;
        while (line[i] != 0) { putchar(line[i]); i = i + 1; }
    } else {
        if (fi <= nf) {
            i = 0;
            while (i < flen[fi - 1]) { putchar(line[fstart[fi - 1] + i]); i = i + 1; }
        }
    }
    return 0;
}

/* pnum: print a non-negative decimal number.
 * Generates digits least-significant first into d[] (v%10 via v-(v/10)*10, since
 * this C subset has no % operator), then emits them in reverse. d[8] holds any
 * 16-bit value. */
int pnum(int v) {
    char d[8];
    int n;
    if (v == 0) { putchar('0'); return 0; }
    n = 0;
    while (v != 0) { d[n] = (v - (v / 10) * 10) + '0'; n = n + 1; v = v / 10; }
    while (n != 0) { n = n - 1; putchar(d[n]); }
    return 0;
}

/* run_action: interpret the action `print item, item, ...` for the current
 * record. An empty action prints $0. Unknown text prints nothing. */
int run_action() {
    char *a;
    int first;
    int fi;
    a = act;
    while (*a == 32) { a = a + 1; }
    if (*a == 0) { pfield(0); putchar(10); return 0; }   /* {} or none -> print $0 */
    /* expect the keyword "print" */
    if (a[0] == 'p' && a[1] == 'r' && a[2] == 'i' && a[3] == 'n' && a[4] == 't') {
        a = a + 5;
    }
    first = 1;
    while (*a != 0) {
        while (*a == 32) { a = a + 1; }
        if (*a == ',') { a = a + 1; while (*a == 32) { a = a + 1; } }
        if (*a != 0) {
            if (first == 0) { putchar(32); }               /* OFS between items */
            first = 0;
            if (*a == '"') {                               /* "string literal" */
                a = a + 1;
                while (*a != 0 && *a != '"') { putchar(*a); a = a + 1; }
                if (*a == '"') { a = a + 1; }
            } else if (*a == '$') {                        /* $0..$9 or $NF */
                a = a + 1;
                if (*a == 'N' && *(a + 1) == 'F') { a = a + 2; pfield(nf); }
                else {
                    fi = 0;
                    while (*a >= '0' && *a <= '9') { fi = fi * 10 + (*a - '0'); a = a + 1; }
                    pfield(fi);
                }
            } else if (*a == 'N' && *(a + 1) == 'R') { a = a + 2; pnum(nr); }
            else if (*a == 'N' && *(a + 1) == 'F') { a = a + 2; pnum(nf); }
            else { a = a + 1; }                            /* skip anything else */
        }
    }
    if (first == 1) { pfield(0); }                          /* `print` with no items -> $0 */
    putchar(10);
    return 0;
}

/* parse_prog: pull the pattern (/re/) and action ({...}) out of the program
 * text p. Sets hasre/re[] and act[]. */
int parse_prog(char *p) {
    int i;
    hasre = 0;
    re[0] = 0;
    act[0] = 0;
    while (*p == 32) { p = p + 1; }
    if (*p == '/') {                          /* /regex/ */
        p = p + 1;
        i = 0;
        while (*p != 0 && *p != '/') { if (i < 79) { re[i] = *p; i = i + 1; } p = p + 1; }
        re[i] = 0;
        hasre = 1;
        if (*p == '/') { p = p + 1; }
    }
    while (*p == 32) { p = p + 1; }
    if (*p == '{') {                          /* { action } */
        p = p + 1;
        i = 0;
        while (*p != 0 && *p != '}') { if (i < 119) { act[i] = *p; i = i + 1; } p = p + 1; }
        act[i] = 0;
    }
    return 0;
}

/* main: parse the command line (optional -F, then the quoted program, then an
 * optional file), then stream records applying the single rule. argstr() returns
 * the whole raw argument tail as one string, which we hand-tokenize here because
 * the shell does not split or de-quote it for us. ASCII 39 = single quote. */
int main() {
    char *a;
    char prog[128];
    int i;
    int q;
    int r;

    a = argstr();
    sepc = 0;
    while (*a == 32) { a = a + 1; }
    if (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H')) {
        puts("usage: awk [-F c] '[/re/]{print items}' [file]   items: $0 $N NF NR \"str\"");
        return 0;
    }
    if (*a == '-' && *(a + 1) == 'F') {       /* -F c  (attached or spaced) */
        a = a + 2;
        while (*a == 32) { a = a + 1; }
        sepc = *a;
        if (*a != 0) { a = a + 1; }
        while (*a == 32) { a = a + 1; }
    }
    /* the program: a quoted token (' or "), else up to the next space */
    i = 0;
    if (*a == 39 || *a == '"') {
        q = *a;
        a = a + 1;
        while (*a != 0 && *a != q) { if (i < 127) { prog[i] = *a; i = i + 1; } a = a + 1; }
        if (*a == q) { a = a + 1; }
    } else {
        while (*a != 0 && *a != 32 && *a != 13) { if (i < 127) { prog[i] = *a; i = i + 1; } a = a + 1; }
    }
    prog[i] = 0;
    parse_prog(prog);

    while (*a == 32) { a = a + 1; }           /* the rest = an input file, or stdin */
    r = openarg(a);   /* opens the named file, or wires up stdin if a is empty; 2 = missing file */
    if (r == 2) { puts("awk: not found"); return 1; }

    nr = 0;
    while (readrec()) {
        nr = nr + 1;
        split();
        if (hasre == 0 || match(re, line)) { run_action(); }
    }
    return 0;
}
