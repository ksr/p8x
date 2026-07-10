/* DEPRECATED (kept for reference, NOT built/shipped): the self-hosted C front
   end (cpp | lex | cc1) is superseded by `cc` (apps/p8xcc.asm), which compiles
   entirely on-target. See os/run.sh and BACKLOG.md. */
/* lex.c — the tokenizer: pass 2 of the on-target C toolchain (cpp | LEX | cc1 | cg).
 *
 *     LEX src.i >src.tok
 *
 * Reads a (preprocessed) C source and emits a token stream — one token per line,
 * "<line> <T> <payload>", matching p8cc.py --tokens exactly:
 *     <n> K int         keyword          <n> N 31          number (decimal)
 *     <n> I main        identifier       <n> S 3 72 105 10 string (count, bytes)
 *     <n> O (           operator         <n> E             end of file
 *
 * Streams the source through the BIOS read stream with a one-char pushback, so
 * it needs no whole-file buffer (it can tokenize sources far larger than the
 * TPA). Line counting matches p8cc.py's lexer to the letter: only a top-level
 * newline counts; a slash-star block comment is skipped WITHOUT counting the
 * newlines inside it. Within the p8cc subset (no ++/--, no break, flat arrays).
 *
 * BIOS: FRESOLVE=$0133, FOPEN=$0124 (buf $FC00), FGETB=$0127.
 */
//#use apath   /* abspath(out, a): a CWD-relative path word -> absolute */

int pb;                            /* one-char pushback (-1 = empty) */
int lno;                           /* current source line (1-based) */
char id[64];                       /* identifier / keyword text */
char sbuf[512];                    /* string-literal bytes (buffered to count) */

int streq(char *a, char *b) {
    int i; i = 0;
    while (a[i] != 0 && a[i] == b[i]) { i = i + 1; }
    return a[i] == b[i];
}

/* gc: next source char, or -1 at EOF. Does NOT count lines. */
int gc() {
    int c;
    if (pb != -1) { c = pb; pb = -1; return c; }
    c = bios(0x0127, 0, 0);                    /* FGETB */
    if (c & 256) { return -1; }
    return c & 255;
}
int ungc(int c) { pb = c; return 0; }

/* emit a decimal number, then a string, then a char */
int edec(int v) {
    char buf[8];
    int n;
    if (v == 0) { putchar('0'); return 0; }
    n = 0;
    while (v != 0) { buf[n] = (v % 10) + '0'; v = v / 10; n = n + 1; }
    while (n != 0) { n = n - 1; putchar(buf[n]); }
    return 0;
}
int es(char *s) { int i; i = 0; while (s[i] != 0) { putchar(s[i]); i = i + 1; } return 0; }
int line_pfx() { edec(lno); putchar(32); return 0; }   /* "<line> " */

int isalp(int c) {
    if (c >= 'A' && c <= 'Z') { return 1; }
    if (c >= 'a' && c <= 'z') { return 1; }
    if (c == '_') { return 1; }
    return 0;
}
int isdig(int c) { if (c >= '0' && c <= '9') { return 1; } return 0; }
int ishex(int c) {
    if (isdig(c)) { return 1; }
    if (c >= 'a' && c <= 'f') { return 1; }
    if (c >= 'A' && c <= 'F') { return 1; }
    return 0;
}
int hexv(int c) {
    if (c >= '0' && c <= '9') { return c - '0'; }
    if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
    return c - 'A' + 10;
}
/* iskw: 1 if id[] is a keyword */
int iskw() {
    if (streq(id, "int")) { return 1; }    if (streq(id, "char")) { return 1; }
    if (streq(id, "void")) { return 1; }   if (streq(id, "struct")) { return 1; }
    if (streq(id, "union")) { return 1; }  if (streq(id, "if")) { return 1; }
    if (streq(id, "else")) { return 1; }   if (streq(id, "while")) { return 1; }
    if (streq(id, "for")) { return 1; }    if (streq(id, "return")) { return 1; }
    return 0;
}

/* escv: value of the escape letter after a backslash (n r t 0 \ ' ") */
int escv(int c) {
    if (c == 'n') { return 10; }   if (c == 'r') { return 13; }
    if (c == 't') { return 9; }    if (c == '0') { return 0; }
    return c;                                  /* \\ \' \" -> the char itself */
}

/* two-char operator? c is the first char, d the second. Emits and returns 1 if
 * (c,d) is one of == != <= >= << >> && || ->, else 0 (caller handles single). */
int twop(int c, int d) {
    if (c == '=' && d == '=') { return 1; }   if (c == '!' && d == '=') { return 1; }
    if (c == '<' && d == '=') { return 1; }   if (c == '>' && d == '=') { return 1; }
    if (c == '<' && d == '<') { return 1; }   if (c == '>' && d == '>') { return 1; }
    if (c == '&' && d == '&') { return 1; }   if (c == '|' && d == '|') { return 1; }
    if (c == '-' && d == '>') { return 1; }
    return 0;
}

int main() {
    char *arg;
    char abs[80];
    int c;
    int d;
    int j;
    int v;

    arg = argstr();
    while (*arg == 32) { arg = arg + 1; }
    if (*arg == 0 || *arg == 13 ||
        (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H'))) {
        puts("usage: LEX src.c   tokenize; token stream to stdout");
        return 0;
    }
    abspath(abs, arg);
    bios(0x0133, abs, 0);                      /* FRESOLVE */
    if (bios(0x0124, 0xFC00, 0) & 256) { puts("lex: cannot open"); return 1; }

    pb = -1;
    lno = 1;
    c = gc();
    while (c != -1) {
        if (c == 10) { lno = lno + 1; c = gc(); }
        else if (c == 32 || c == 9 || c == 13) { c = gc(); }
        else if (c == '#') {                    /* cpp line: skip to newline */
            while (c != -1 && c != 10) { c = gc(); }
        }
        else if (c == '/') {
            d = gc();
            if (d == '/') { while (c != -1 && c != 10) { c = gc(); } }
            else if (d == '*') {                /* block comment: no line counting */
                c = gc();
                d = gc();
                while (c != -1 && !(c == '*' && d == '/')) { c = d; d = gc(); }
                c = gc();
            }
            else { ungc(d); line_pfx(); es("O /"); putchar(10); c = gc(); }
        }
        else if (isalp(c)) {                    /* identifier or keyword */
            j = 0;
            while (isalp(c) || isdig(c)) {
                if (j < 63) { id[j] = c; j = j + 1; }
                c = gc();
            }
            id[j] = 0;
            line_pfx();
            if (iskw()) { es("K "); } else { es("I "); }
            es(id); putchar(10);
        }
        else if (isdig(c)) {                    /* number (decimal or 0x hex) */
            v = 0;
            d = gc();
            if (c == '0' && (d == 'x' || d == 'X')) {
                c = gc();
                while (ishex(c)) { v = v * 16 + hexv(c); c = gc(); }
            } else {
                v = c - '0';
                c = d;
                while (isdig(c)) { v = v * 10 + (c - '0'); c = gc(); }
            }
            line_pfx(); es("N "); edec(v & 0xFFFF); putchar(10);
        }
        else if (c == 39) {                     /* char literal 'x' or '\x' */
            c = gc();
            if (c == 92) { d = gc(); v = escv(d); } else { v = c; }
            c = gc();                            /* closing quote */
            line_pfx(); es("N "); edec(v & 0xFFFF); putchar(10);
            c = gc();
        }
        else if (c == 34) {                     /* string literal */
            line_pfx(); putchar('S'); putchar(32);
            /* count the bytes first is awkward while streaming; instead scan into
             * a buffer, then print count + bytes. */
            j = 0;
            c = gc();
            while (c != -1 && c != 34) {
                if (c == 92) { d = gc(); sbuf[j] = escv(d); }
                else { sbuf[j] = c; }
                if (j < 511) { j = j + 1; }
                c = gc();
            }
            edec(j);
            v = 0;
            while (v < j) { putchar(32); edec(sbuf[v] & 255); v = v + 1; }
            putchar(10);
            c = gc();
        }
        else {                                  /* operator: two-char then one */
            d = gc();
            line_pfx(); putchar('O'); putchar(32);
            if (twop(c, d)) { putchar(c); putchar(d); c = gc(); }
            else { putchar(c); ungc(d); c = gc(); }
            putchar(10);
        }
    }
    line_pfx(); putchar('E'); putchar(10);
    return 0;
}
