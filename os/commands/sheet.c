/* sheet.c -- a basic spreadsheet for the P8X graphics desktop.
 *
 * A grid of cells with a menu/formula bar, drawn full-screen on the GL card.
 * A cell holds a NUMBER (16-bit integer) or a FORMULA (starts with '='). A
 * formula is an integer expression over + - * / with the usual precedence and
 * parentheses, cell references (A1..H12), and four range functions:
 *   SUM(A1:A5)  AVG(A1:A5)  MAX(A1:A5)  MIN(A1:A5)
 * AVG truncates (integer division); division by zero and bad refs show #ERR.
 *
 * Keyboard AND mouse: arrows move the selection, a digit / - / + / = starts
 * editing, Enter commits (and steps down), Esc cancels, Backspace clears a cell;
 * click a cell to select it, or click SAVE / LOAD / QUIT in the bar. The sheet
 * loads/saves a line-based file (one "REF raw" per non-empty cell).
 *
 * No float on this machine, so everything is 16-bit signed -- and p8cc's '/' and
 * '<' are UNSIGNED, so sdiv()/slt() do the sign handling by hand.
 *
 * -d chains back to desk, -w to the resident wdesk; otherwise quit -> finder.
 */
//#use abi     /* FRESOLVE/FDELETE/FWOPEN/FPUTB/FCLOSE/FOPEN/FGETB, RDBUF, SYS_EXEC, argstr */
//#use mem     /* GFXPRES / GTSUSP -- the graphics + screen-claim flags */
//#use ptr     /* ptr_ev / ptr_init / ptr_done / ptr_x / ptr_y / ptr_key */

//#define GLDATA  0xFF50
//#define GLSTAT  0xFF51

/* grid geometry (fits 480x272, window coords y-UP) */
//#define NC     8            /* columns A..H            */
//#define NR     12           /* rows 1..12              */
//#define NCELL  96           /* NC*NR                   */
//#define RL     32           /* raw bytes per cell      */
//#define GX0    32           /* left edge of column A   */
//#define CW     54           /* cell width              */
//#define GTOP   240          /* top edge of row 0       */
//#define CH     18           /* cell height             */

char raw[3072];               /* NCELL * RL, the raw text of each cell */
int  val[96];                 /* computed integer value */
int  cerr[96];                /* 1 = this cell is in error (#ERR) */
int  selc; int selr;          /* selected column / row */
char ebuf[34]; int elen;      /* edit buffer while typing a cell */
char fpath[64];               /* the sheet file */
int  fromdesk; int fromwm;

/* evaluator scan state */
char *fp;                     /* formula scan pointer */
int  ferr;                    /* error during the current eval */
int  refc; int refr;          /* last cell reference parsed */

/* ---- GL emission ----------------------------------------------------------- */
int gp(int v) { while (peek(GLSTAT) & 128) { } poke(GLDATA, v); return 0; }
int gw(int v) { gp(v & 255); gp((v / 256) & 255); return 0; }
int pen(int c) { gp(6); gp((c >> 11) & 31); gp((c >> 5) & 63); gp(c & 31); return 0; }
int gtext(int x, int y, char *s) {
    int i;
    gp(18); gw(x); gw(y); gw(0);              /* MOVE3 x,y,0 */
    i = 0; while (s[i]) { i = i + 1; }
    gp(128); gp(i);                           /* TEXT count */
    i = 0; while (s[i]) { gp(s[i]); i = i + 1; }
    return 0;
}
int fillrect(int x0, int y0, int x1, int y1) {
    gp(224); gp(1); gp(16); gw(x0); gw(y0); gp(52); gw(x1); gw(y1); gp(224); gp(0);
    return 0;
}
int gline(int x0, int y0, int x1, int y1) {
    gp(16); gw(x0); gw(y0); gp(40); gw(x1); gw(y1);
    return 0;
}
int gsetup() {
    gp(179); gw(0); gw(479); gw(0); gw(271);  /* WINDOW  full */
    gp(178); gw(0); gw(479); gw(0); gw(271);  /* VWPORT  full */
    gp(176); gw(0);                           /* PROJCT 0 */
    gp(144);                                  /* MDIDEN   */
    gp(129); gw(256);                         /* TSIZE 1.0 */
    return 0;
}

/* ---- small integer utilities (p8cc / and < are UNSIGNED) ------------------- */
int isdig(int c) { return (c >= '0') && (c <= '9'); }
int isalp(int c) { return ((c >= 'A') && (c <= 'Z')) || ((c >= 'a') && (c <= 'z')); }
int upc(int c) { if ((c >= 'a') && (c <= 'z')) { return c - 32; } return c; }

int sdiv(int a, int b) {                      /* signed a / b */
    int sa; int sb; int q;
    sa = 0; sb = 0;
    if (a & 32768) { a = 0 - a; sa = 1; }
    if (b & 32768) { b = 0 - b; sb = 1; }
    q = a / b;
    if (sa != sb) { q = 0 - q; }
    return q;
}
int slt(int a, int b) {                       /* signed a < b */
    int na; int nb;
    na = a & 32768; nb = b & 32768;
    if (na && (nb == 0)) { return 1; }        /* a<0, b>=0 */
    if ((na == 0) && nb) { return 0; }
    return a < b;                             /* same sign: unsigned order agrees */
}
/* v -> decimal string in out (signed) */
int itoa(int v, char *out) {
    char t[8]; int n; int i; int neg;
    neg = 0;
    if (v & 32768) { neg = 1; v = 0 - v; }
    n = 0;
    if (v == 0) { t[n] = '0'; n = n + 1; }
    while (v) { t[n] = '0' + (v - (v / 10) * 10); v = v / 10; n = n + 1; }
    i = 0;
    if (neg) { out[i] = '-'; i = i + 1; }
    while (n > 0) { n = n - 1; out[i] = t[n]; i = i + 1; }
    out[i] = 0;
    return 0;
}

/* ---- the formula evaluator ------------------------------------------------- */
int skipsp() { while (*fp == 32) { fp = fp + 1; } return 0; }

int rd_num() {                                /* an unsigned decimal literal */
    int v;
    v = 0;
    while (isdig(*fp)) { v = v * 10 + (*fp - '0'); fp = fp + 1; }
    return v;
}
int rd_ref() {                                /* a cell ref at fp -> refc/refr */
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
int do_func() {                               /* SUM/AVG/MAX/MIN ( ref : ref ) */
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
int rd_alpha() {                              /* a cell ref (A1) or a function */
    int ci;
    if (isdig(fp[1])) {                       /* letter then digit -> cell ref */
        rd_ref();
        if (ferr) { return 0; }
        ci = refr * NC + refc;
        if (cerr[ci]) { ferr = 1; }
        return val[ci];
    }
    return do_func();
}
/* precedence-climbing, ONE self-recursive function (p8cc rejects mutual
 * recursion / forward decls). minp = the lowest operator precedence this call
 * will consume; parentheses and the RHS recurse into eval() itself. */
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

/* ---- cell values ----------------------------------------------------------- */
int parse_num(char *s) {                      /* a plain number cell */
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
    if (r[0] == 0) { val[ci] = 0; cerr[ci] = 0; return 0; }   /* empty */
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
int recalc() {                                /* iterate to a fixed point */
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

/* ---- rendering ------------------------------------------------------------- */
int cellx(int c) { return GX0 + c * CW; }
int rtop(int r) { return GTOP - r * CH; }     /* top edge (window y) of row r */
int refstr(int c, int r, char *out) {         /* e.g. "B3" */
    int i;
    out[0] = 'A' + c; i = 1;
    itoa(r + 1, out + 1);
    return 0;
}
int draw_cellval(int ci) {                    /* the value text of one cell */
    char s[10]; char *r; int cc; int rr;
    r = raw + ci * RL;
    if (r[0] == 0) { return 0; }              /* empty: nothing */
    rr = ci / NC; cc = ci - rr * NC;
    if (cerr[ci]) { s[0] = '#'; s[1] = 'E'; s[2] = 'R'; s[3] = 'R'; s[4] = 0; }
    else { itoa(val[ci], s); }
    pen(65535);
    gtext(cellx(cc) + 3, rtop(rr) - 13, s);
    return 0;
}
int draw_grid() {
    int i; int gb; char h[6];                 /* h: decl at the TOP -- p8cc does not
                                                 handle a local declared inside a loop */
    gb = rtop(NR);                            /* bottom edge of the grid */
    pen(0); fillrect(0, 0, 479, GTOP + 16);   /* clear grid + header band */
    pen(12 << 5);                             /* dim green grid lines */
    i = 0;                                    /* horizontal rules */
    while (i <= NR) { gline(0, rtop(i), cellx(NC), rtop(i)); i = i + 1; }
    gline(0, gb, 0, GTOP + 16);               /* verticals */
    gline(GX0, gb, GX0, GTOP + 16);
    i = 0;
    while (i < NC) { gline(cellx(i + 1), gb, cellx(i + 1), GTOP + 16); i = i + 1; }
    gline(0, GTOP + 16, cellx(NC), GTOP + 16);/* top of the header band */
    /* column headers A..H, row headers 1..NR */
    pen(31 << 6);                             /* header text: green */
    i = 0;
    while (i < NC) {
        h[0] = 'A' + i; h[1] = 0;
        gtext(cellx(i) + CW / 2 - 3, GTOP + 3, h);
        i = i + 1;
    }
    i = 0;
    while (i < NR) {
        itoa(i + 1, h);
        gtext(4, rtop(i) - 13, h);
        i = i + 1;
    }
    return 0;
}
int draw_sel() {                              /* highlight the selected cell */
    int x0; int y1;
    x0 = cellx(selc); y1 = rtop(selr);
    pen(31);                                  /* blue outline, 2 nested rects */
    gline(x0, y1, x0 + CW, y1); gline(x0, y1 - CH, x0 + CW, y1 - CH);
    gline(x0, y1, x0, y1 - CH); gline(x0 + CW, y1, x0 + CW, y1 - CH);
    gline(x0 + 1, y1 - 1, x0 + CW - 1, y1 - 1); gline(x0 + 1, y1 - CH + 1, x0 + CW - 1, y1 - CH + 1);
    gline(x0 + 1, y1 - 1, x0 + 1, y1 - CH + 1); gline(x0 + CW - 1, y1 - 1, x0 + CW - 1, y1 - CH + 1);
    return 0;
}
int draw_bar(int editing) {                   /* menu + formula bar (top) */
    char ref[8]; char *r;
    pen(6 << 5); fillrect(0, GTOP + 17, 479, 271);   /* bar background */
    pen(65535);
    refstr(selc, selr, ref);
    gtext(4, 261, ref);
    gp(6); gp(31); gp(63); gp(0);                    /* yellow content */
    if (editing) { gtext(40, 261, ebuf); }
    else { r = raw + (selr * NC + selc) * RL; if (r[0]) { gtext(40, 261, r); } }
    pen(31 << 6);                                    /* green menu buttons */
    gtext(330, 261, "SAVE");
    gtext(378, 261, "LOAD");
    gtext(426, 261, "QUIT");
    return 0;
}
int draw_all(int editing) {
    int i;
    draw_grid();
    draw_sel();
    i = 0; while (i < NCELL) { draw_cellval(i); i = i + 1; }
    draw_bar(editing);
    return 0;
}

/* ---- file save / load ------------------------------------------------------ */
int putbytes(char *s) { int i; i = 0; while (s[i]) { bios(FPUTB, 0, s[i]); i = i + 1; } return 0; }
int save() {
    char ref[8]; int ci; char *r;
    bios(FRESOLVE, fpath, 0);
    bios(FDELETE, fpath, 0);
    bios(FRESOLVE, fpath, 0);
    bios(FWOPEN, 0, 0);
    ci = 0;
    while (ci < NCELL) {
        r = raw + ci * RL;
        if (r[0]) {
            refstr(ci - (ci / NC) * NC, ci / NC, ref);      /* "REF raw\n" per cell */
            putbytes(ref); bios(FPUTB, 0, 32); putbytes(r); bios(FPUTB, 0, 10);
        }
        ci = ci + 1;
    }
    bios(FCLOSE, 0, 0);
    return 0;
}
int load() {
    int r; int st; int c; int rr; int ci; int i; char *dst;
    ci = 0; while (ci < 3072) { raw[ci] = 0; ci = ci + 1; }
    bios(FRESOLVE, fpath, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { return 0; }   /* no file yet */
    st = 0; c = 0; rr = 0; ci = 0; i = 0; dst = raw;
    while (1) {
        r = bios(FGETB, 0, 0);
        if (r & 256) { r = 10; st = 9; }             /* EOF: flush last line */
        r = r & 255;
        if (st == 0) {                               /* column letter */
            if (isalp(r)) { c = upc(r) - 'A'; st = 1; rr = 0; }
        } else if (st == 1) {                        /* row digits */
            if (isdig(r)) { rr = rr * 10 + (r - '0'); }
            else { ci = (rr - 1) * NC + c; dst = raw + ci * RL; i = 0; st = 2; }
        } else if (st == 2) {                        /* the raw content to EOL */
            if ((r == 10) || (r == 13)) {
                if ((ci >= 0) && (ci < NCELL)) { dst[i] = 0; }
                st = 0;
            } else if (i < RL - 1) { dst[i] = r; i = i + 1; }
        }
        if (st == 9) { return 0; }
    }
    return 0;
}

/* ---- cell editing ---------------------------------------------------------- */
int begin_fresh(int k) { ebuf[0] = k; ebuf[1] = 0; elen = 1; return 0; }
int begin_edit() {                            /* load the current cell to edit */
    char *r; int i;
    r = raw + (selr * NC + selc) * RL;
    i = 0; while (r[i] && (i < RL - 1)) { ebuf[i] = r[i]; i = i + 1; }
    ebuf[i] = 0; elen = i;
    return 0;
}
int commit_edit() {                           /* ebuf -> selected cell */
    char *r; int i;
    r = raw + (selr * NC + selc) * RL;
    i = 0; while (i < elen) { r[i] = ebuf[i]; i = i + 1; }
    r[i] = 0;
    return 0;
}
int clear_cell() { char *r; r = raw + (selr * NC + selc) * RL; r[0] = 0; return 0; }

/* mouse hit test: panel (x,y) -> select a cell, or a bar button (1 save / 2 load
 * / 3 quit / 0 none). */
int hit(int x, int y) {
    int c; int r;
    if (y >= GTOP + 17) {                     /* the menu bar */
        if ((x >= 330) && (x < 372)) { return 1; }
        if ((x >= 378) && (x < 420)) { return 2; }
        if ((x >= 426) && (x < 468)) { return 3; }
        return 0;
    }
    if ((x < GX0) || (x >= cellx(NC))) { return 0; }
    if ((y > GTOP) || (y <= rtop(NR))) { return 0; }
    c = (x - GX0) / CW;
    r = (GTOP - y) / CH;
    if ((c >= 0) && (c < NC) && (r >= 0) && (r < NR)) { selc = c; selr = r; return 4; }
    return 0;
}

int main() {
    int ev; int k; int going; int editing; int h; char *a; int i;
    if (peek(GFXPRES) == 0) { puts("?No display"); return 1; }
    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (a[0] == '-') { if (a[1] == 'd') { fromdesk = 1; } if (a[1] == 'w') { fromwm = 1; } a = a + 2; while (*a == 32) { a = a + 1; } }
    if ((*a == '/') || ((*a >= 'A') && (*a <= 'Z'))) {
        i = 0; while (a[i] && (a[i] != 13) && (a[i] != 32) && (i < 60)) { fpath[i] = a[i]; i = i + 1; }
        fpath[i] = 0;
    } else {
        fpath[0] = '/'; fpath[1] = 'S'; fpath[2] = 'H'; fpath[3] = 'E';
        fpath[4] = 'E'; fpath[5] = 'T'; fpath[6] = '.'; fpath[7] = 'S';
        fpath[8] = 'S'; fpath[9] = 0;
    }
    poke(GTSUSP, 1);
    gsetup();
    selc = 0; selr = 0; editing = 0;
    load();
    recalc();
    ptr_init();
    draw_all(0);
    going = 1;
    while (going) {
        ev = ptr_ev();
        if (ev == 0) {
            k = ptr_key;
            if (editing) {
                if ((k == 13) || (k == 10)) { commit_edit(); editing = 0; recalc(); if (selr < NR - 1) { selr = selr + 1; } draw_all(0); }
                else if (k == 27) { editing = 0; draw_all(0); }
                else if ((k == 8) || (k == 127)) { if (elen > 0) { elen = elen - 1; ebuf[elen] = 0; } draw_bar(1); }
                else if ((k >= 32) && (k < 127) && (elen < RL - 2)) { ebuf[elen] = k; elen = elen + 1; ebuf[elen] = 0; draw_bar(1); }
            } else {
                if (k == 128) { if (selr > 0) { selr = selr - 1; } draw_all(0); }
                else if (k == 129) { if (selr < NR - 1) { selr = selr + 1; } draw_all(0); }
                else if (k == 130) { if (selc < NC - 1) { selc = selc + 1; } draw_all(0); }
                else if (k == 131) { if (selc > 0) { selc = selc - 1; } draw_all(0); }
                else if ((k == 'q') || (k == 'Q') || (k == 24)) { going = 0; }
                else if ((k == 's') || (k == 'S') || (k == 19)) { save(); }
                else if ((k == 'o') || (k == 'O') || (k == 15)) { load(); recalc(); draw_all(0); }
                else if ((k == 8) || (k == 127)) { clear_cell(); recalc(); draw_all(0); }
                else if (k == 13) { begin_edit(); editing = 1; draw_bar(1); }
                else if (isdig(k) || (k == '-') || (k == '+') || (k == '=') || (k == '.')) { begin_fresh(k); editing = 1; draw_bar(1); }
            }
        } else if (ev == 1) {                 /* a mouse press */
            if (editing) { commit_edit(); editing = 0; recalc(); }
            h = hit(ptr_x, ptr_y);
            if (h == 1) { save(); }
            else if (h == 2) { load(); recalc(); draw_all(0); }
            else if (h == 3) { going = 0; }
            else { draw_all(0); }             /* h==4 selected, or a miss: repaint */
        }
    }
    ptr_done();
    poke(GTSUSP, 0);
    if (fromdesk) { bios(SYS_EXEC, "/bin/desk.bin", 0); }
    if (fromwm) { bios(SYS_EXEC, "/bin/wdesk.bin -r", 0); }
    bios(SYS_EXEC, "/bin/finder.bin", 0);
    return 0;
}
