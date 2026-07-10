/* DEPRECATED (kept for reference, NOT built/shipped): the self-hosted C front
   end (cpp | lex | cc1) is superseded by `cc` (apps/p8xcc.asm), which compiles
   entirely on-target. See os/run.sh and BACKLOG.md. */
/* cc1.c - the parser: pass 3 of the on-target C toolchain (cpp | lex | cc1 | cg).
 *
 *     cc1 src.tok >src.ast
 *
 * Reads a LEX token stream (pass-2 output) and writes the serialized AST that
 * the code generator (cg) consumes. The wire format is p8cc.py's --ast: a
 * whitespace-separated pre-order atom stream (see ast_ser in p8cc.py). cc1 must
 * reproduce it byte-for-byte.
 *
 * Parsing is recursive descent, mirroring p8cc.py's P class. The AST is emitted
 * as it is parsed, so there is no in-memory tree of the whole program. The one
 * wrinkle is that infix operators (a+b, a=b, a&&b, postfix a[i]/a.b) parse the
 * left operand BEFORE the operator tag is known, yet pre-order wants the tag
 * first. Since the BIOS write stream is append-only, cc1 splices the tag in
 * front of the already-emitted left operand with einsert() inside eb[]. An
 * einsert only ever reaches back to the start of the CURRENT expression, so
 * eb[] is flushed at every statement boundary (never mid-expression): the
 * buffer holds at most one statement's worth of atoms, bounding memory even
 * for large functions.
 *
 * Every atom is written with a trailing space; flushing writes eb[] verbatim,
 * so atoms stay single-space separated across flushes exactly like Python's
 * " ".join(...). The program ends with a " ;" terminator + newline.
 *
 * BIOS: FRESOLVE=$0133, FOPEN=$0124 (buf $FC00), FGETB=$0127. p8cc subset:
 * no ++/--, no break, flat arrays, unsigned 16-bit compares.
 */
//#use apath   /* abspath(out, a): a CWD-relative path word -> absolute */

/* token kinds */
int K_EOF;
int K_NUM;
int K_STR;
int K_ID;
int K_KW;
int K_OP;

/* --- input token window: current t0, lookahead t1, t2 (parser peeks i+2) --- */
int t0k;  int t0v;  char t0n[64];  char t0s[512];  int t0sl;
int t1k;  int t1v;  char t1n[64];  char t1s[512];  int t1sl;
int t2k;  int t2v;  char t2n[64];  char t2s[512];  int t2sl;

int pb;                            /* input stream pushback (-1 = empty) */

/* --- output: current statement/unit buffered in eb[], spliced then flushed --- */
char eb[6144];   int ebn;
char pbuf[128];  int pbn;          /* prefix builder for einsert */

/* --- parser scratch --- */
char gb[64];   int gp;             /* base type / ptr depth from base_and_ptr */
char fb[64];   int fp;  char fn[64];   /* saved function/gvar return type + name */
char idname[64];                   /* last identifier seen by primary() */
int  is_id;                        /* is the current postfix base a bare id? */

int streq(char *a, char *b) {
    int i; i = 0;
    while (a[i] != 0 && a[i] == b[i]) { i = i + 1; }
    return a[i] == b[i];
}
int scopy(char *d, char *s) {
    int i; i = 0;
    while (s[i] != 0) { d[i] = s[i]; i = i + 1; }
    d[i] = 0; return 0;
}

/* ---- input token stream ------------------------------------------------- */
int gc() {
    int c;
    if (pb != -1) { c = pb; pb = -1; return c; }
    c = bios(0x0127, 0, 0);                    /* FGETB */
    if (c & 256) { return -1; }
    return c & 255;
}
/* gword: next whitespace-delimited word into buf; returns length (0 at EOF) */
int gword(char *buf) {
    int c; int n;
    c = gc();
    while (c == 32 || c == 10 || c == 13 || c == 9) { c = gc(); }
    if (c == -1) { buf[0] = 0; return 0; }
    n = 0;
    while (c != -1 && c != 32 && c != 10 && c != 13 && c != 9) {
        if (n < 63) { buf[n] = c; n = n + 1; }
        c = gc();
    }
    buf[n] = 0; return n;
}
int gnum() {
    char b[16]; int i; int r;
    gword(b); r = 0; i = 0;
    while (b[i] >= '0' && b[i] <= '9') { r = r * 10 + (b[i] - '0'); i = i + 1; }
    return r;
}
/* readtok: decode one LEX record "<line> <T> <payload>" into the t2 slot */
int readtok() {
    char lno[16]; char kd[8]; int n; int cnt; int i;
    n = gword(lno);
    if (n == 0) { t2k = K_EOF; t2sl = 0; return 0; }
    gword(kd);
    t2sl = 0;
    if (kd[0] == 'K')      { t2k = K_KW;  gword(t2n); }
    else if (kd[0] == 'I') { t2k = K_ID;  gword(t2n); }
    else if (kd[0] == 'N') { t2k = K_NUM; t2v = gnum(); }
    else if (kd[0] == 'O') { t2k = K_OP;  gword(t2n); }
    else if (kd[0] == 'S') {
        t2k = K_STR; cnt = gnum(); i = 0;
        while (i < cnt) { n = gnum(); if (i < 512) { t2s[i] = n; } i = i + 1; }
        t2sl = cnt;
    }
    else { t2k = K_EOF; }
    return 0;
}
/* window copies: t2->t1, t1->t0, t2->t0 (copy only the valid string length) */
int cp21() {
    int i; t1k = t2k; t1v = t2v; t1sl = t2sl;
    scopy(t1n, t2n); i = 0; while (i < t2sl) { t1s[i] = t2s[i]; i = i + 1; }
    return 0;
}
int cp10() {
    int i; t0k = t1k; t0v = t1v; t0sl = t1sl;
    scopy(t0n, t1n); i = 0; while (i < t1sl) { t0s[i] = t1s[i]; i = i + 1; }
    return 0;
}
int cp20() {
    int i; t0k = t2k; t0v = t2v; t0sl = t2sl;
    scopy(t0n, t2n); i = 0; while (i < t2sl) { t0s[i] = t2s[i]; i = i + 1; }
    return 0;
}
int adv() { cp10(); cp21(); readtok(); return 0; }
/* cvis: current token is keyword/punct textually equal to s */
int cvis(char *s) { return (t0k == K_KW || t0k == K_OP) && streq(t0n, s); }
int accept(char *s) { if (cvis(s)) { adv(); return 1; } return 0; }
int eat(char *s) { if (!cvis(s)) { puts("cc1: unexpected token"); puts(s); } else { adv(); } return 0; }

/* ---- output atoms (trailing-space invariant) ---------------------------- */
int e_word(char *s) {
    int i; i = 0;
    while (s[i] != 0) { eb[ebn] = s[i]; ebn = ebn + 1; i = i + 1; }
    eb[ebn] = 32; ebn = ebn + 1; return 0;
}
int e_uint(int v) {                /* unsigned decimal + space */
    char b[8]; int k;
    if (v == 0) { eb[ebn] = '0'; ebn = ebn + 1; eb[ebn] = 32; ebn = ebn + 1; return 0; }
    k = 0;
    while (v != 0) { b[k] = (v % 10) + '0'; v = v / 10; k = k + 1; }
    while (k != 0) { k = k - 1; eb[ebn] = b[k]; ebn = ebn + 1; }
    eb[ebn] = 32; ebn = ebn + 1; return 0;
}
int e_snum(int neg, int v) {       /* optional '-' then decimal + space */
    if (neg && v != 0) { eb[ebn] = '-'; ebn = ebn + 1; }
    e_uint(v); return 0;
}
int e_bytes() {                    /* current STR token: <len> then bytes */
    int i; e_uint(t0sl); i = 0;
    while (i < t0sl) { e_uint(t0s[i] & 255); i = i + 1; }
    return 0;
}
/* prefix builder + splice-at-position (for infix -> pre-order) */
int p_reset() { pbn = 0; return 0; }
int p_word(char *s) {
    int i; i = 0;
    while (s[i] != 0) { pbuf[pbn] = s[i]; pbn = pbn + 1; i = i + 1; }
    pbuf[pbn] = 32; pbn = pbn + 1; return 0;
}
int p_uint(int v) {
    char b[8]; int k;
    if (v == 0) { pbuf[pbn] = '0'; pbn = pbn + 1; pbuf[pbn] = 32; pbn = pbn + 1; return 0; }
    k = 0;
    while (v != 0) { b[k] = (v % 10) + '0'; v = v / 10; k = k + 1; }
    while (k != 0) { k = k - 1; pbuf[pbn] = b[k]; pbn = pbn + 1; }
    pbuf[pbn] = 32; pbn = pbn + 1; return 0;
}
int einsert(int pos) {             /* splice pbuf[0..pbn) into eb at pos */
    int i; int n; n = pbn;
    i = ebn;
    while (i > pos) { eb[i + n - 1] = eb[i - 1]; i = i - 1; }
    i = 0; while (i < n) { eb[pos + i] = pbuf[i]; i = i + 1; }
    ebn = ebn + n; return 0;
}
int flush() {                      /* write eb verbatim, reset (call only at a
                                      statement boundary, never mid-expression) */
    int i; i = 0;
    while (i < ebn) { putchar(eb[i]); i = i + 1; }
    ebn = 0; return 0;
}

/* ---- grammar (mirrors p8cc.py P) ---------------------------------------- */
int oplevel(char *s) {             /* binary precedence level, 99 if not binary */
    if (streq(s, "|")) { return 0; }
    if (streq(s, "^")) { return 1; }
    if (streq(s, "&")) { return 2; }
    if (streq(s, "==") || streq(s, "!=")) { return 3; }
    if (streq(s, "<") || streq(s, ">") || streq(s, "<=") || streq(s, ">=")) { return 4; }
    if (streq(s, "<<") || streq(s, ">>")) { return 5; }
    if (streq(s, "+") || streq(s, "-")) { return 6; }
    if (streq(s, "*") || streq(s, "/") || streq(s, "%")) { return 7; }
    return 99;
}

int bap() {                        /* base_and_ptr -> gb, gp */
    if (cvis("struct") || cvis("union")) { adv(); scopy(gb, t0n); adv(); }
    else if (cvis("int") || cvis("char") || cvis("void")) { scopy(gb, t0n); adv(); }
    else { puts("cc1: expected a type"); }
    gp = 0;
    while (cvis("*")) { gp = gp + 1; adv(); }
    return 0;
}

int expr();                        /* fwd: recursion within the expression grammar
                                      is self-recursive per function; the mutual
                                      calls below are resolved by definition order */

int primary() {
    if (t0k == K_NUM) { e_word("num"); e_uint(t0v); adv(); is_id = 0; }
    else if (t0k == K_STR) { e_word("str"); e_bytes(); adv(); is_id = 0; }
    else if (t0k == K_ID) { e_word("id"); e_word(t0n); scopy(idname, t0n); adv(); is_id = 1; }
    else if (cvis("(")) { adv(); expr(); eat(")"); is_id = 0; }
    else { puts("cc1: unexpected token in expression"); adv(); is_id = 0; }
    return 0;
}
int postfix() {
    int p; int go; p = ebn; primary(); go = 1;
    while (go) {
        if (cvis("(")) {
            if (!is_id) { puts("cc1: call of non-function"); }
            ebn = p; e_word("call"); e_word(idname);
            adv();
            if (!cvis(")")) { expr(); while (cvis(",")) { adv(); expr(); } }
            eat(")"); e_word(";"); is_id = 0;
        }
        else if (cvis("[")) { p_reset(); p_word("index"); einsert(p); adv(); expr(); eat("]"); is_id = 0; }
        else if (cvis(".")) { p_reset(); p_word("member"); einsert(p); adv(); e_word(t0n); adv(); is_id = 0; }
        else if (cvis("->")) { p_reset(); p_word("arrow"); einsert(p); adv(); e_word(t0n); adv(); is_id = 0; }
        else { go = 0; }
    }
    return 0;
}
int unary() {
    char op[4];
    if (cvis("-") || cvis("!") || cvis("&") || cvis("*") || cvis("~")) {
        scopy(op, t0n); adv(); e_word("unary"); e_word(op); unary();
    } else { postfix(); }
    return 0;
}
int binary(int lvl) {
    int p; char op[4];
    if (lvl >= 8) { unary(); return 0; }
    p = ebn; binary(lvl + 1);
    while (t0k == K_OP && oplevel(t0n) == lvl) {
        scopy(op, t0n); adv();
        p_reset(); p_word("bin"); p_word(op); einsert(p);
        binary(lvl + 1);
    }
    return 0;
}
int logand() {
    int p; p = ebn; binary(0);
    while (cvis("&&")) { adv(); p_reset(); p_word("logand"); einsert(p); binary(0); }
    return 0;
}
int logor() {
    int p; p = ebn; logand();
    while (cvis("||")) { adv(); p_reset(); p_word("logor"); einsert(p); logand(); }
    return 0;
}
int assign_() {
    int p; p = ebn; logor();
    if (cvis("=")) { adv(); p_reset(); p_word("assign"); einsert(p); assign_(); }
    return 0;
}
int expr() { assign_(); return 0; }

int initializer() {
    int neg; int done;
    if (cvis("{")) {
        adv(); e_word("initlist");
        if (!cvis("}")) {
            initializer(); done = 0;
            while (cvis(",") && done == 0) { adv(); if (cvis("}")) { done = 1; } else { initializer(); } }
        }
        eat("}"); e_word(";");
    }
    else if (t0k == K_STR) { e_word("initstr"); e_bytes(); adv(); }
    else {
        neg = 0; if (cvis("-")) { neg = 1; adv(); }
        if (t0k != K_NUM) { puts("cc1: non-constant global initializer"); }
        e_word("initnum"); e_snum(neg, t0v); adv();
    }
    return 0;
}

int stmt();
int block() {
    e_word("block"); eat("{"); flush();
    while (!cvis("}")) { stmt(); }
    eat("}"); e_word(";"); flush(); return 0;
}
int stmt() {
    char nm[64]; int cnt;
    if (cvis("{")) { block(); return 0; }
    if (cvis("int") || cvis("char") || cvis("struct") || cvis("union")) {
        bap(); scopy(nm, t0n); adv(); cnt = 0;
        if (cvis("[")) { adv(); cnt = t0v; adv(); eat("]"); }
        e_word("decl"); e_word(gb); e_uint(gp); e_uint(cnt); e_word(nm);
        if (cvis("=")) { adv(); e_word("1"); expr(); } else { e_word("0"); }
        eat(";"); flush(); return 0;
    }
    if (cvis("if")) {
        adv(); e_word("if"); eat("("); expr(); eat(")"); flush(); stmt();
        if (cvis("else")) { adv(); e_word("1"); flush(); stmt(); } else { e_word("0"); flush(); }
        return 0;
    }
    if (cvis("while")) { adv(); e_word("while"); eat("("); expr(); eat(")"); flush(); stmt(); return 0; }
    if (cvis("for")) {
        adv(); e_word("for"); eat("(");
        if (cvis(";")) { e_word("0"); } else { e_word("1"); expr(); } eat(";");
        if (cvis(";")) { e_word("0"); } else { e_word("1"); expr(); } eat(";");
        if (cvis(")")) { e_word("0"); } else { e_word("1"); expr(); } eat(")");
        flush(); stmt(); return 0;
    }
    if (cvis("return")) {
        adv(); e_word("return");
        if (cvis(";")) { e_word("0"); } else { e_word("1"); expr(); }
        eat(";"); flush(); return 0;
    }
    if (cvis(";")) { adv(); e_word("empty"); flush(); return 0; }
    e_word("expr"); expr(); eat(";"); flush(); return 0;
}

int param() {                      /* one parameter: base ptr 0 name */
    bap(); e_word(gb); e_uint(gp); e_uint(0); e_word(t0n); adv(); return 0;
}
int structdef() {
    char kind[8]; char tag[64]; char mn[64]; int cnt;
    scopy(kind, t0n); adv();
    scopy(tag, t0n); adv();
    eat("{");
    e_word("structdef"); e_word(kind); e_word(tag);
    while (!cvis("}")) {
        bap(); e_word(gb); e_uint(gp);
        scopy(mn, t0n); adv(); cnt = 0;
        if (cvis("[")) { adv(); cnt = t0v; adv(); eat("]"); }
        e_uint(cnt); e_word(mn);
        eat(";");
    }
    eat("}"); eat(";"); e_word(";"); flush(); return 0;
}
int toplevel() {
    int pp; int proto; int arr; int cnt; int infer;
    if ((cvis("struct") || cvis("union")) && t2k == K_OP && streq(t2n, "{")) { structdef(); return 0; }
    bap(); scopy(fb, gb); fp = gp;
    scopy(fn, t0n); adv();
    if (cvis("(")) {
        adv(); pp = ebn;
        if (!cvis(")")) { param(); while (cvis(",")) { adv(); param(); } }
        eat(")");
        p_reset(); proto = 0;
        if (cvis(";")) { adv(); proto = 1; p_word("proto"); } else { p_word("func"); }
        p_word(fb); p_uint(fp); p_uint(0); p_word(fn);
        einsert(pp);
        e_word(";"); flush();
        if (!proto) { block(); }
    } else {
        e_word("gvar"); e_word(fb); e_uint(fp);
        arr = 0; cnt = 0; infer = 0;
        if (cvis("[")) { arr = 1; adv(); if (cvis("]")) { infer = 1; } else { cnt = t0v; adv(); } eat("]"); }
        e_uint(arr);
        if (infer) { e_word("-1"); } else { e_uint(cnt); }
        e_word(fn);
        if (cvis("=")) { adv(); e_word("1"); initializer(); } else { e_word("0"); }
        eat(";"); flush();
    }
    return 0;
}

int main() {
    char *arg; char abs[80];
    K_EOF = 0; K_NUM = 1; K_STR = 2; K_ID = 3; K_KW = 4; K_OP = 5;

    arg = argstr();
    while (*arg == 32) { arg = arg + 1; }
    if (*arg == 0 || *arg == 13 ||
        (*arg == '-' && (*(arg + 1) == 'h' || *(arg + 1) == 'H'))) {
        puts("usage: cc1 src.tok   parse a token stream; AST to stdout");
        return 0;
    }
    abspath(abs, arg);
    bios(0x0133, abs, 0);                      /* FRESOLVE */
    if (bios(0x0124, 0xFC00, 0) & 256) { puts("cc1: cannot open"); return 1; }

    pb = -1;
    readtok(); cp20();                         /* prime the window: t0 */
    readtok(); cp21();                         /* t1 */
    readtok();                                 /* t2 */

    ebn = 0;
    while (t0k != K_EOF) { ebn = 0; toplevel(); flush(); }
    putchar(';'); putchar('\n');               /* program terminator */
    return 0;
}
