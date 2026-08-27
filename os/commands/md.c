/* md.c -- render a Markdown file on the console.
 *
 *     MD FILE.MD        styled: bold headings, dim code, wrapped prose
 *     MD -p FILE.MD     plain: identical layout, no escape codes
 *
 * A line-oriented subset renderer in the man/more family, so the guides
 * in /docs read well at the bench. The console is a raw byte stream into
 * the user's terminal, so styling is ordinary ANSI escapes (SGR only);
 * -p suppresses them for dumb terminals and for deterministic tests.
 *
 * The subset (one classification per line):
 *   #..######   headings: blank line, bold (h1/h2 also underlined);
 *               plain mode draws an =/- underline row instead
 *   - * +  1.   list items: hanging indent, wrapped
 *   >           quote: "  | " prefix, wrapped
 *   ```         code fence toggle: verbatim, 2-space indent, dim
 *   |...|       tables: buffered, column widths measured, re-emitted
 *               aligned (the separator row becomes dashes)
 *   ---/***     horizontal rule
 *   (prose)     word-wrapped at 78 columns
 * Inline, outside code fences: **bold**, `code` (dim), [text](url) ->
 * "text (url)". Underscores and nesting are NOT interpreted.
 *
 * Pager: --More-- every 22 lines via CONIN, exactly like more; q quits.
 * Long unbreakable words emit as-is (the terminal wraps). Off-subset
 * markdown passes through as prose -- rendering never fails. */
char path[80];
char lin[240];                  /* one raw source line                  */
char wrd[160];                  /* one word being assembled             */
char tbf[3600];                 /* table buffer: up to 20 rows x 180    */
int  tbw[10];                   /* table column widths (<= 10 columns)  */

//#use apath
//#use abi

int ansi;                       /* 1 = emit SGR escapes                 */
int nrow;                       /* rows printed since the last prompt   */
int qflag;                      /* user pressed q at --More--           */
int infen;                      /* inside a ``` fence                   */
int tbn;                        /* buffered table rows                  */
int ateof;                      /* input exhausted                      */
int col;                        /* visible column while wrapping        */
int bold;                       /* inline state, carried across wraps   */
int dim;

/* ---- console helpers ---------------------------------------------------- */

int esc(char *s) {              /* one SGR sequence, ansi mode only */
    if (ansi == 0) { return 0; }
    putchar(27); putchar('[');
    while (*s != 0) { putchar(*s); s = s + 1; }
    putchar('m');
    return 0;
}

int attrs() {                   /* (re)assert the current inline attrs */
    esc("0");
    if (bold) { esc("1"); }
    if (dim)  { esc("2"); }
    return 0;
}

int nl() {                      /* newline + the pager */
    int k;
    putchar(10);
    nrow = nrow + 1;
    if (nrow >= 22) {
        nrow = 0;
        if (qflag == 0) {
            esc("7");
            putchar('-'); putchar('-'); putchar('M'); putchar('o');
            putchar('r'); putchar('e'); putchar('-'); putchar('-');
            esc("0");
            k = bios(CONIN, 0, 0) & 255;
            putchar(13);
            putchar(32); putchar(32); putchar(32); putchar(32);
            putchar(32); putchar(32); putchar(32); putchar(32);
            putchar(13);
            if (k == 'q' || k == 'Q') { qflag = 1; }
        }
    }
    return 0;
}

int spaces(int n) {
    while (n) { putchar(32); n = n - 1; }
    return 0;
}

/* ---- input -------------------------------------------------------------- */

/* rdln: next source line into lin (CR and LF stripped, tabs -> spaces,
 * capped at 238). Returns 1 if a line was read, 0 at end of file. */
int rdln() {
    int c; int i;
    if (ateof) { return 0; }
    i = 0;
    c = bios(FGETB, 0, 0);
    if (c & 256) { ateof = 1; return 0; }
    while ((c & 256) == 0 && (c & 255) != 10) {
        c = c & 255;
        if (c == 9) { c = 32; }
        if (c != 13 && i < 238) { lin[i] = c; i = i + 1; }
        c = bios(FGETB, 0, 0);
    }
    if (c & 256) { ateof = 1; }
    lin[i] = 0;
    return 1;
}

/* ---- inline emission with wrapping -------------------------------------- */

/* emitw: print the assembled word (wrd, visible width vw), wrapping to a
 * fresh line at `ind` columns first if it will not fit in 78. */
int emitw(int vw, int ind) {
    char *p;
    if (col + vw > 78 && col > ind) {
        nl();
        spaces(ind);
        col = ind;
        if (bold || dim) { attrs(); }
    }
    p = wrd;
    while (*p != 0) { putchar(*p); p = p + 1; }
    col = col + vw;
    return 0;
}

/* flow: render s as wrapped prose from the current position. Inline marks
 * (** ` [](...)) become attributes; ind is the hanging indent. */
int flow(char *s, int ind) {
    int wi; int vw; int sp;
    wi = 0; vw = 0;
    while (*s != 0 && qflag == 0) {
        sp = 0;
        if (*s == 32) { sp = 1; }
        else if (*s == '*' && *(s + 1) == '*') {
            wrd[wi] = 0;
            if (wi) { emitw(vw, ind); wi = 0; vw = 0; }
            bold = 1 - bold;
            if (bold) { esc("1"); } else { attrs(); }
            s = s + 2;
        }
        else if (*s == '`') {
            wrd[wi] = 0;
            if (wi) { emitw(vw, ind); wi = 0; vw = 0; }
            dim = 1 - dim;
            if (dim) { esc("2"); } else { attrs(); }
            s = s + 1;
        }
        else if (*s == '[') {
            /* [text](url) -> text (url); anything else: literal '[' */
            char *t; int ok;
            t = s + 1; ok = 0;
            while (*t != 0 && *t != ']') { t = t + 1; }
            if (*t == ']' && *(t + 1) == '(') { ok = 1; }
            if (ok) {
                s = s + 1;
                while (*s != ']') {          /* the text, worded out */
                    if (*s == 32) {
                        wrd[wi] = 0; emitw(vw, ind);
                        wrd[0] = 32; wrd[1] = 0; emitw(1, ind);
                        wi = 0; vw = 0;
                    } else if (wi < 156) {
                        wrd[wi] = *s; wi = wi + 1; vw = vw + 1;
                    }
                    s = s + 1;
                }
                s = s + 2;                   /* past "](" */
                if (wi < 155) { wrd[wi] = 32; wrd[wi+1] = '('; wi = wi + 2; vw = vw + 2; }
                while (*s != 0 && *s != ')') {
                    if (wi < 156) { wrd[wi] = *s; wi = wi + 1; vw = vw + 1; }
                    s = s + 1;
                }
                if (*s == ')') { s = s + 1; }
                if (wi < 156) { wrd[wi] = ')'; wi = wi + 1; vw = vw + 1; }
            } else {
                if (wi < 156) { wrd[wi] = '['; wi = wi + 1; vw = vw + 1; }
                s = s + 1;
            }
        }
        else {
            if (wi < 156) { wrd[wi] = *s; wi = wi + 1; vw = vw + 1; }
            s = s + 1;
        }
        if (sp) {
            wrd[wi] = 0;
            if (wi) { emitw(vw, ind); }
            wi = 0; vw = 0;
            if (col < 78) {
                wrd[0] = 32; wrd[1] = 0;
                if (col > ind) { emitw(1, ind); }
            }
            s = s + 1;
        }
    }
    wrd[wi] = 0;
    if (wi) { emitw(vw, ind); }
    return 0;
}

/* para: one classified body line rendered as flowed text. pre is the
 * printed prefix, ind the hanging indent for continuations. */
int para(char *pre, char *s, int ind) {
    spaces(0);
    col = 0;
    while (*pre != 0) { putchar(*pre); col = col + 1; pre = pre + 1; }
    bold = 0; dim = 0;
    flow(s, ind);
    attrs();
    nl();
    return 0;
}

/* ---- tables ------------------------------------------------------------- */

/* cellw: measure/emit one row from the buffer. When put=0 just record
 * column widths; when put=1 print the row padded to tbw[]. A separator
 * row (cells of ---) prints as dashes. */
int cellw(char *r, int put) {
    int ci; int w; int sep; int j;
    ci = 0;
    if (*r == '|') { r = r + 1; }
    while (*r != 0 && ci < 10) {
        char *c; int n;
        while (*r == 32) { r = r + 1; }
        c = r; n = 0; sep = 1;
        while (*r != 0 && *r != '|') {
            if (*r != 32 && *r != '-' && *r != ':') { sep = 0; }
            r = r + 1;
        }
        n = r - c;
        while (n && *(c + n - 1) == 32) { n = n - 1; }   /* rtrim */
        if (put == 0) {
            if (sep == 0 && n > tbw[ci]) { tbw[ci] = n; }
        } else {
            w = tbw[ci];
            if (ci == 0) { putchar(32); putchar(32); }
            if (sep) {
                j = 0;
                while (j < w) { putchar('-'); j = j + 1; }
            } else {
                j = 0;
                while (j < n) { putchar(*(c + j)); j = j + 1; }
                while (j < w) { putchar(32); j = j + 1; }
            }
            putchar(32); putchar(32);
        }
        ci = ci + 1;
        if (*r == '|') { r = r + 1; }
    }
    if (put) { nl(); }
    return 0;
}

int tflush() {                  /* measure all buffered rows, emit aligned */
    int r;
    if (tbn == 0) { return 0; }
    r = 0;
    while (r < 10) { tbw[r] = 0; r = r + 1; }
    r = 0;
    while (r < tbn) { cellw(tbf + r * 180, 0); r = r + 1; }
    r = 0;
    while (r < tbn && qflag == 0) { cellw(tbf + r * 180, 1); r = r + 1; }
    tbn = 0;
    return 0;
}

/* ---- line classification ------------------------------------------------ */

int starts(char *s, char *p) {
    while (*p != 0) {
        if (*s != *p) { return 0; }
        s = s + 1; p = p + 1;
    }
    return 1;
}

int hrule(char *s) {            /* ---, ***, ___ alone on the line */
    int n; int c;
    c = *s;
    if (c != '-' && c != '*' && c != '_') { return 0; }
    n = 0;
    while (*s == c || *s == 32) { if (*s == c) { n = n + 1; } s = s + 1; }
    if (*s == 0 && n >= 3) { return 1; }
    return 0;
}

int render() {                  /* the whole file, line by line */
    int i; int lvl; char *s; char *t; char *u; int ind;
    while (rdln() && qflag == 0) {
        s = lin;
        if (infen || starts(s, "```")) {              /* code fences */
            if (starts(s, "```")) {
                tflush();
                infen = 1 - infen;
                if (infen == 0) { nl(); }
            } else {
                col = 0;
                esc("2");
                putchar(32); putchar(32);
                while (*s != 0) { putchar(*s); s = s + 1; }
                esc("0");
                nl();
            }
        }
        else if (*s == '|') {                         /* table rows buffer */
            if (tbn < 20) {
                i = 0;
                while (*s != 0 && i < 178) { *(tbf + tbn * 180 + i) = *s; s = s + 1; i = i + 1; }
                *(tbf + tbn * 180 + i) = 0;
                tbn = tbn + 1;
            }
        }
        else if (*s == '#') {                         /* headings */
            tflush();
            lvl = 0;
            while (*s == '#') { lvl = lvl + 1; s = s + 1; }
            while (*s == 32) { s = s + 1; }
            nl();
            col = 0;
            if (lvl <= 2) { esc("1"); esc("4"); } else { esc("1"); }
            i = 0;
            while (*s != 0) {                     /* marks stripped */
                if (*s != '*' && *s != 96) { putchar(*s); i = i + 1; }
                s = s + 1;
            }
            esc("0");
            nl();
            if (ansi == 0) {                          /* plain: underline row */
                int u;
                u = '-';
                if (lvl == 1) { u = '='; }
                col = 0;
                while (i) { putchar(u); i = i - 1; }
                nl();
            }
        }
        else if (hrule(s)) {
            tflush();
            col = 0;
            i = 0;
            while (i < 78) { putchar('-'); i = i + 1; }
            nl();
        }
        else if (starts(s, "> ")) {
            tflush();
            para("  | ", s + 2, 4);
        }
        else if (*s == '>' && *(s + 1) == 0) {
            tflush();
            para("  | ", s + 1, 4);
        }
        else {                                        /* lists then prose */
            t = s; ind = 0;
            while (*t == 32) { t = t + 1; ind = ind + 1; }
            if ((*t == '-' || *t == '*' || *t == '+') && *(t + 1) == 32) {
                tflush();
                spaces(0);
                col = 0;
                spaces(ind + 2); col = ind + 2;
                putchar('-'); putchar(32); col = col + 2;
                bold = 0; dim = 0;
                flow(t + 2, ind + 4);
                attrs();
                nl();
            }
            else if (*t >= '0' && *t <= '9') {
                u = t;
                while (*u >= '0' && *u <= '9') { u = u + 1; }
                if (*u == '.' && *(u + 1) == 32) {
                    tflush();
                    col = 0;
                    spaces(ind + 2); col = ind + 2;
                    while (t <= u) { putchar(*t); t = t + 1; col = col + 1; }
                    putchar(32); col = col + 1;
                    bold = 0; dim = 0;
                    flow(u + 2, ind + 5);
                    attrs();
                    nl();
                } else {
                    tflush();
                    para("", s, 0);
                }
            }
            else if (*s == 0) { tflush(); nl(); }     /* blank line */
            else { tflush(); para("", s, 0); }
        }
    }
    tflush();
    return 0;
}

/* ---- entry -------------------------------------------------------------- */

int main() {
    char *ap;
    ap = argstr();
    while (*ap == 32) { ap = ap + 1; }
    ansi = 1;
    if (*ap == '-' && *(ap + 1) == 'p') {
        ansi = 0;
        ap = ap + 2;
        while (*ap == 32) { ap = ap + 1; }
    }
    if (*ap == 0 || *ap == 13 ||
        (*ap == '-' && (*(ap + 1) == 'h' || *(ap + 1) == 'H'))) {
        puts("usage: MD [-p] FILE.MD    render markdown (-p: no ANSI styling)");
        return 0;
    }
    abspath(path, ap);
    bios(FRESOLVE, path, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { puts("?File not found"); return 1; }
    nrow = 0; qflag = 0; infen = 0; tbn = 0; ateof = 0;
    render();
    return 0;
}
