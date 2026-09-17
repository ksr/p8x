/* sheet_host.c -- HOST unit test for the sheet.c formula evaluator.
 * Mirrors the pure (no peek/poke/bios) functions of os/commands/sheet.c and
 * drives them with known inputs. Keep in step with sheet.c's evaluator.
 * Build: cc -O2 -o sheet_host sheet_host.c && ./sheet_host */
#include <stdio.h>
#include <string.h>

#define NC 8
#define NR 12
#define NCELL 96
#define RL 32

char raw[3072];
int  val[96];
int  cerr[96];
char *fp;
int  ferr;
int  refc; int refr;

/* ---- copied verbatim from os/commands/sheet.c (the pure evaluator) --------- */
int isdig(int c) { return (c >= '0') && (c <= '9'); }
int isalp(int c) { return ((c >= 'A') && (c <= 'Z')) || ((c >= 'a') && (c <= 'z')); }
int upc(int c) { if ((c >= 'a') && (c <= 'z')) { return c - 32; } return c; }
int sdiv(int a, int b) {
    int sa; int sb; int q;
    sa = 0; sb = 0;
    if (a & 32768) { a = 0 - a; sa = 1; }
    if (b & 32768) { b = 0 - b; sb = 1; }
    q = a / b;
    if (sa != sb) { q = 0 - q; }
    return q;
}
int slt(int a, int b) {
    int na; int nb;
    na = a & 32768; nb = b & 32768;
    if (na && (nb == 0)) { return 1; }
    if ((na == 0) && nb) { return 0; }
    return a < b;
}
int skipsp() { while (*fp == 32) { fp = fp + 1; } return 0; }
int rd_num() {
    int v; v = 0;
    while (isdig(*fp)) { v = v * 10 + (*fp - '0'); fp = fp + 1; }
    return v;
}
int rd_ref() {
    refc = upc(*fp) - 'A';
    fp = fp + 1;
    refr = 0;
    if (isdig(*fp) == 0) { ferr = 1; return 0; }
    while (isdig(*fp)) { refr = refr * 10 + (*fp - '0'); fp = fp + 1; }
    refr = refr - 1;
    if ((refc < 0) || (refc >= NC) || (refr < 0) || (refr >= NR)) { ferr = 1; }
    return 0;
}
int eq3(char *s, int a, int b, int c) {
    return (s[0] == a) && (s[1] == b) && (s[2] == c) && (s[3] == 0);
}
int do_func() {
    char id[5]; int n; int fn;
    int c1; int r1; int c2; int r2; int lc; int hc; int lr; int hr;
    int acc; int cnt; int mn; int mx; int v; int c; int r; int ci;
    n = 0;
    while (isalp(*fp) && (n < 4)) { id[n] = upc(*fp); n = n + 1; fp = fp + 1; }
    id[n] = 0;
    fn = 0 - 1;
    if (eq3(id, 'S', 'U', 'M')) { fn = 0; }
    if (eq3(id, 'A', 'V', 'G')) { fn = 1; }
    if (eq3(id, 'M', 'A', 'X')) { fn = 2; }
    if (eq3(id, 'M', 'I', 'N')) { fn = 3; }
    if (fn < 0) { ferr = 1; return 0; }
    if (*fp != '(') { ferr = 1; return 0; }
    fp = fp + 1;
    rd_ref(); c1 = refc; r1 = refr;
    if (*fp != ':') { ferr = 1; return 0; }
    fp = fp + 1;
    rd_ref(); c2 = refc; r2 = refr;
    if (*fp != ')') { ferr = 1; return 0; }
    fp = fp + 1;
    if (ferr) { return 0; }
    lc = c1; hc = c2; if (c1 > c2) { lc = c2; hc = c1; }
    lr = r1; hr = r2; if (r1 > r2) { lr = r2; hr = r1; }
    acc = 0; cnt = 0; mn = 32767; mx = 0 - 32768;
    r = lr;
    while (r <= hr) {
        c = lc;
        while (c <= hc) {
            ci = r * NC + c;
            if (cerr[ci]) { ferr = 1; }
            v = val[ci];
            acc = acc + v; cnt = cnt + 1;
            if (slt(v, mn)) { mn = v; }
            if (slt(mx, v)) { mx = v; }
            c = c + 1;
        }
        r = r + 1;
    }
    if (fn == 0) { return acc; }
    if (fn == 1) { if (cnt == 0) { return 0; } return sdiv(acc, cnt); }
    if (fn == 2) { return mx; }
    return mn;
}
int rd_alpha() {
    int ci;
    if (isdig(fp[1])) {
        rd_ref();
        if (ferr) { return 0; }
        ci = refr * NC + refc;
        if (cerr[ci]) { ferr = 1; }
        return val[ci];
    }
    return do_func();
}
int eval(int minp) {
    int v; int c; int op; int prec; int rhs; int go;
    skipsp();
    c = *fp;
    v = 0;
    if (c == '(') { fp = fp + 1; v = eval(0); skipsp(); if (*fp == ')') { fp = fp + 1; } else { ferr = 1; } }
    else if (c == '-') { fp = fp + 1; v = 0 - eval(3); }
    else if (c == '+') { fp = fp + 1; v = eval(3); }
    else if (isdig(c)) { v = rd_num(); }
    else if (isalp(c)) { v = rd_alpha(); }
    else { ferr = 1; }
    go = 1;
    while (go) {
        skipsp();
        op = *fp;
        prec = 0;
        if ((op == '+') || (op == '-')) { prec = 1; }
        if ((op == '*') || (op == '/')) { prec = 2; }
        if (prec == 0) { go = 0; }
        else if (prec < minp) { go = 0; }
        else {
            fp = fp + 1;
            rhs = eval(prec + 1);
            if (op == '+') { v = v + rhs; }
            if (op == '-') { v = v - rhs; }
            if (op == '*') { v = v * rhs; }
            if (op == '/') { if (rhs == 0) { ferr = 1; } else { v = sdiv(v, rhs); } }
        }
    }
    return v;
}
int parse_num(char *s) {
    int i; int neg; int v;
    i = 0; neg = 0; v = 0;
    if (s[0] == '-') { neg = 1; i = 1; }
    else if (s[0] == '+') { i = 1; }
    while (isdig(s[i])) { v = v * 10 + (s[i] - '0'); i = i + 1; }
    if (neg) { v = 0 - v; }
    return v;
}
int eval_cell(int ci) {
    char *r;
    r = raw + ci * RL;
    ferr = 0;
    if (r[0] == 0) { val[ci] = 0; cerr[ci] = 0; return 0; }
    if (r[0] == '=') {
        fp = r + 1;
        val[ci] = eval(0);
        skipsp();
        if ((*fp != 0) && (*fp != 13)) { ferr = 1; }
        cerr[ci] = ferr;
    } else {
        val[ci] = parse_num(r);
        cerr[ci] = 0;
    }
    return 0;
}
int recalc() {
    int pass; int i; int ch; int old;
    pass = 0;
    while (pass < 24) {
        ch = 0;
        i = 0;
        while (i < NCELL) {
            old = val[i];
            eval_cell(i);
            if (val[i] != old) { ch = 1; }
            i = i + 1;
        }
        if (ch == 0) { pass = 999; } else { pass = pass + 1; }
    }
    return 0;
}

/* ---- the test harness (host only) ------------------------------------------ */
static int fails = 0;
static void setcell(int col, int row, const char *s) { strcpy(raw + (row * NC + col) * RL, s); }
static int cellval(int col, int row) { return val[row * NC + col]; }
static int cellerr(int col, int row) { return cerr[row * NC + col]; }
static void expect(const char *what, int got, int want) {
    if (got != want) { printf("  FAIL %s: got %d want %d\n", what, got, want); fails = 1; }
}

int main(void) {
    memset(raw, 0, sizeof raw);
    /* column A: 1,2,3,4,5 ; B1 various formulas */
    setcell(0, 0, "1"); setcell(0, 1, "2"); setcell(0, 2, "3");
    setcell(0, 3, "4"); setcell(0, 4, "5");
    setcell(0, 5, "-6");                          /* A6 negative */
    setcell(1, 0, "=1+2*3");                      /* 7  (precedence) */
    setcell(1, 1, "=(1+2)*3");                    /* 9  (parens) */
    setcell(1, 2, "=SUM(A1:A5)");                 /* 15 */
    setcell(1, 3, "=AVG(A1:A5)");                 /* 3  (15/5) */
    setcell(1, 4, "=MAX(A1:A6)");                 /* 5 */
    setcell(1, 5, "=MIN(A1:A6)");                 /* -6 (signed min) */
    setcell(2, 0, "=A1+A2+A3");                   /* 6  (cell refs) */
    setcell(2, 1, "=10/3");                        /* 3  (int div) */
    setcell(2, 2, "=0-6/2");                       /* -3 (signed div) */
    setcell(2, 3, "=A5*A5");                       /* 25 */
    setcell(2, 4, "=B3+C1");                       /* 15+6 = 21 (formula refs formulas) */
    setcell(2, 5, "=5/0");                         /* #ERR div by zero */
    setcell(3, 0, "=ZZ9");                          /* #ERR bad ref */
    setcell(3, 1, "=1+");                           /* #ERR trailing */
    setcell(3, 2, "=avg(a1:a5)");                   /* lowercase -> 3 */

    recalc();

    expect("B1 1+2*3", cellval(1,0), 7);
    expect("B2 (1+2)*3", cellval(1,1), 9);
    expect("B3 SUM(A1:A5)", cellval(1,2), 15);
    expect("B4 AVG(A1:A5)", cellval(1,3), 3);
    expect("B5 MAX(A1:A6)", cellval(1,4), 5);
    expect("B6 MIN(A1:A6)", cellval(1,5), -6);
    expect("C1 A1+A2+A3", cellval(2,0), 6);
    expect("C2 10/3", cellval(2,1), 3);
    expect("C3 0-6/2", cellval(2,2), -3);
    expect("C4 A5*A5", cellval(2,3), 25);
    expect("C5 B3+C1 (chained)", cellval(2,4), 21);
    expect("C6 5/0 is err", cellerr(2,5), 1);
    expect("D1 bad ref is err", cellerr(3,0), 1);
    expect("D2 trailing is err", cellerr(3,1), 1);
    expect("D3 lowercase avg", cellval(3,2), 3);
    /* a formula that references an error cell propagates the error */
    setcell(4, 0, "=C6+1"); recalc();
    expect("E1 refs err cell", cellerr(4,0), 1);

    if (fails) { printf("SHEET-HOST TEST: FAIL\n"); return 1; }
    printf("SHEET-HOST TEST: PASS (precedence, parens, refs, ranges, SUM/AVG/MAX/MIN, signed div, errors)\n");
    return 0;
}
