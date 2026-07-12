/* vi.c — a minimal VT100 screen editor for the P8X.  RUN /BIN/VI.BIN NAME
 *
 * A modal, vi-flavoured editor. Needs a VT100-compatible terminal (it drives the
 * cursor with ANSI escapes over the serial console). Reads keys RAW and unbuffered
 * through the BIOS CONIN ($0100, no echo) and writes with CONOUT ($0103), so it
 * bypasses the OS line editor and stdout redirection entirely.
 *
 * Model: the file is a flat buffer of fixed-width lines — line i occupies
 * line[i*80 .. i*80+79], NUL-terminated (p8cc has no 2-D arrays). The cursor is
 * at (cy, cx) and `top` is the first on-screen line; this maps 1:1 onto the
 * terminal, so redraw is cheap: cursor moves just reposition, a character edit
 * repaints one line, and only a line insert/delete or a scroll repaints the whole
 * screen — important at real serial baud.
 *
 * NORMAL mode:
 *   h j k l   left/down/up/right        0 $   line start / end
 *   i         insert before cursor      a A   append after cursor / at line end
 *   o         open a line below         x     delete the character
 *   d d       delete the line           G     go to the last line
 *   u         undo the last change      / n   search forward / repeat
 *   :         command line -> w (write) q (quit) wq / x (write+quit) q! (force)
 * Undo is single-level (op-based): it reverts the last x / dd / o / single-line
 * insert. A search is a literal substring, forward, wrapping once.
 * INSERT mode: type text; Enter splits the line; Backspace deletes; Esc -> NORMAL.
 *
 * Screen is 24x80 (VT100 default): 23 text rows + a status/command row. Lines
 * longer than 78 chars, or files taller than 110 lines, are truncated (v0 limits).
 * Within the p8cc subset: no ++/--, declarations at the top of each function,
 * no break/continue, functions defined before use.
 *
 * BIOS: CONIN=$0100, CONOUT=$0103, FRESOLVE=$0133, FOPEN=$0124, FGETB=$0127,
 * FWOPEN=$012A, FPUTB=$012D, FCLOSE=$0130.  Read buffer at $FC00.
 */
//#use apath   /* abspath(out, a): CWD-prefix a relative path (FRESOLVE starts at root) */

char path[80];
char line[8800];         /* 110 lines x 80 cols, flat; line i at line[i*80..] */
int  nlines;             /* number of lines in the buffer (>=1) */
int  cy;                 /* cursor line index */
int  cx;                 /* cursor column */
int  top;                /* first visible line index */
int  mode;               /* 0 = NORMAL, 1 = INSERT */
int  dirty;              /* unsaved changes */
int  done;               /* set to quit */
char cmd[40];            /* ':' command-line text */
char pat[40];            /* last '/' search pattern */
int  havepat;            /* a search pattern has been entered */
/* single-level undo: op-based so it costs one saved line, not a whole 2nd buffer.
 * uop 0=none 1=restore line[uy]=usave  2=delete the line at uy  3=insert usave at uy.
 * (Undo of a structural change during an INSERT session is dropped — see splitline.) */
char usave[80];
int  uop;
int  uy;
int  ux;

/* ---- terminal primitives (raw, unbuffered, straight to the console) -------- */
int rawkey() { return bios(0x0100, 0, 0) & 255; }        /* CONIN: one key, no echo */
int outc(int c) { bios(0x0103, 0, c & 255); return 0; }  /* CONOUT: one char */
int outs(char *s) { int i; i = 0; while (s[i] != 0) { outc(s[i]); i = i + 1; } return 0; }
int outn(int n) {                                        /* decimal, for ANSI args */
    if (n >= 10) { outn(n / 10); }
    outc(48 + n % 10);
    return 0;
}
int esc() { outc(27); outc('['); return 0; }             /* CSI */
int gotoxy(int r, int c) { esc(); outn(r); outc(';'); outn(c); outc('H'); return 0; }  /* 1-based */
int clrscr() { esc(); outc('2'); outc('J'); return 0; }
int clreol() { esc(); outc('K'); return 0; }

/* ---- flat line buffer helpers ---------------------------------------------- */
int llen(int i) {                                /* length of line i */
    int b;
    int j;
    b = i * 80;
    j = 0;
    while (line[b + j] != 0) { j = j + 1; }
    return j;
}

/* ---- file load / save ------------------------------------------------------ */
/* load: read `p` into the line buffer; 1 if not found. Splits on LF, drops CR. */
int load(char *p) {
    int c;
    int col;
    bios(0x0133, p, 0);                          /* FRESOLVE */
    nlines = 0; cx = 0; cy = 0; top = 0;
    if (bios(0x0124, 0xFC00, 0) & 256) {         /* FOPEN; C=1 -> new file */
        nlines = 1; line[0] = 0;
        return 1;
    }
    col = 0;
    c = bios(0x0127, 0, 0);                       /* FGETB */
    while ((c & 256) == 0) {
        c = c & 255;
        if (c == 10) {                            /* LF -> end of line */
            line[nlines * 80 + col] = 0;
            nlines = nlines + 1;
            col = 0;
            if (nlines >= 110) { return 0; }
        } else if (c != 13) {
            if (col < 79) { line[nlines * 80 + col] = c; col = col + 1; }
        }
        c = bios(0x0127, 0, 0);
    }
    line[nlines * 80 + col] = 0;                  /* final (unterminated) line */
    if (col > 0 || nlines == 0) { nlines = nlines + 1; }
    if (nlines == 0) { nlines = 1; line[0] = 0; }
    return 0;
}

/* save: write each line + LF to `p` (the Unix line ending — P8X convention). */
int save(char *p) {
    int i;
    int b;
    int j;
    bios(0x0133, p, 0);                          /* FRESOLVE (dir + leaf) */
    bios(0x012A, 0, 0);                          /* FWOPEN */
    i = 0;
    while (i < nlines) {
        b = i * 80;
        j = 0;
        while (line[b + j] != 0) { bios(0x012D, 0, line[b + j]); j = j + 1; }
        bios(0x012D, 0, 10);                     /* LF (was CRLF; conform to Unix) */
        i = i + 1;
    }
    bios(0x0130, 0, 0);                          /* FCLOSE */
    dirty = 0;
    return 0;
}

/* ---- redraw ---------------------------------------------------------------- */
int drawrow(int r) {                             /* screen text row r (0-based) */
    int li;
    int b;
    int j;
    gotoxy(r + 1, 1);
    li = top + r;
    if (li < nlines) {
        b = li * 80;
        j = 0;
        while (line[b + j] != 0) { outc(line[b + j]); j = j + 1; }
    } else {
        outc('~');
    }
    clreol();
    return 0;
}
int status() {                                   /* row 24: mode + name + dirty */
    gotoxy(24, 1);
    if (mode == 1) { outs("-- INSERT --  "); } else { outs("              "); }
    outs(path);
    if (dirty) { outs(" [+]"); }
    clreol();
    return 0;
}
int placecur() { gotoxy(cy - top + 1, cx + 1); return 0; }
int redraw() {
    int r;
    clrscr();
    r = 0;
    while (r < 23) { drawrow(r); r = r + 1; }
    status();
    placecur();
    return 0;
}
int scroll() {                                   /* keep cursor on screen; 1 if moved */
    if (cy < top) { top = cy; return 1; }
    if (cy > top + 22) { top = cy - 22; return 1; }
    return 0;
}

/* ---- editing --------------------------------------------------------------- */
int clampx() {
    int n;
    n = llen(cy);
    if (cx > n) { cx = n; }
    if (cx < 0) { cx = 0; }
    return 0;
}
int inschar(int c) {                             /* insert c at (cy,cx) */
    int b;
    int n;
    int j;
    b = cy * 80;
    n = llen(cy);
    if (n >= 78) { return 0; }
    j = n;
    while (j > cx) { line[b + j] = line[b + j - 1]; j = j - 1; }
    line[b + cx] = c;
    line[b + n + 1] = 0;
    cx = cx + 1;
    dirty = 1;
    return 0;
}
int delchar() {                                  /* delete char under cursor */
    int b;
    int j;
    b = cy * 80;
    if (cx >= llen(cy)) { return 0; }
    j = cx;
    while (line[b + j] != 0) { line[b + j] = line[b + j + 1]; j = j + 1; }
    dirty = 1;
    return 0;
}
int copyline(int dst, int src) {                 /* line[dst] = line[src] */
    int db;
    int sb;
    int k;
    db = dst * 80; sb = src * 80;
    k = 0;
    while (line[sb + k] != 0) { line[db + k] = line[sb + k]; k = k + 1; }
    line[db + k] = 0;
    return 0;
}
int opendown() {                                 /* empty line after cy */
    int i;
    if (nlines >= 110) { return 0; }
    i = nlines;
    while (i > cy + 1) { copyline(i, i - 1); i = i - 1; }
    line[(cy + 1) * 80] = 0;
    nlines = nlines + 1;
    cy = cy + 1; cx = 0; dirty = 1;
    return 0;
}
int delline() {                                  /* delete line cy */
    int i;
    if (nlines <= 1) { line[0] = 0; cx = 0; dirty = 1; return 0; }
    i = cy;
    while (i < nlines - 1) { copyline(i, i + 1); i = i + 1; }
    nlines = nlines - 1;
    if (cy >= nlines) { cy = nlines - 1; }
    cx = 0; dirty = 1;
    return 0;
}
int splitline() {                                /* Enter in INSERT: break at cx */
    int i;
    int b;
    int k;
    if (nlines >= 110) { return 0; }
    i = nlines;
    while (i > cy + 1) { copyline(i, i - 1); i = i - 1; }
    b = cy * 80;
    k = 0;
    while (line[b + cx + k] != 0) { line[(cy + 1) * 80 + k] = line[b + cx + k]; k = k + 1; }
    line[(cy + 1) * 80 + k] = 0;
    line[b + cx] = 0;
    nlines = nlines + 1;
    cy = cy + 1; cx = 0; dirty = 1;
    return 0;
}

/* ---- ':' command line ------------------------------------------------------ */
int docmd() {
    int k;
    int c;
    gotoxy(24, 1); outc(':'); clreol();
    k = 0;
    c = rawkey();
    while (c != 13 && c != 10) {
        if (c == 27) { return 0; }                /* Esc cancels */
        if (c == 8 || c == 127) {
            if (k > 0) { k = k - 1; outc(8); outc(' '); outc(8); }
        } else if (k < 38) {
            cmd[k] = c; k = k + 1; outc(c);
        }
        c = rawkey();
    }
    cmd[k] = 0;
    if (cmd[0] == 'q' && cmd[1] == 0) {
        if (dirty == 0) { done = 1; }
        else { gotoxy(24, 1); outs("no write since change (:q! to force)"); clreol(); }
        return 0;
    }
    if (cmd[0] == 'q' && cmd[1] == '!') { done = 1; return 0; }
    if (cmd[0] == 'w' && cmd[1] == 0) { save(path); return 0; }
    if (cmd[0] == 'w' && cmd[1] == 'q') { save(path); done = 1; return 0; }
    if (cmd[0] == 'x' && cmd[1] == 0) { save(path); done = 1; return 0; }
    gotoxy(24, 1); outs("?unknown command"); clreol();
    return 0;
}

/* ---- undo (single level, op-based) ----------------------------------------- */
int saveline() {                                 /* copy line[cy] into usave */
    int b; int k;
    b = cy * 80; k = 0;
    while (line[b + k] != 0) { usave[k] = line[b + k]; k = k + 1; }
    usave[k] = 0;
    return 0;
}
int snap1() { saveline(); uop = 1; uy = cy; ux = cx; return 0; }   /* restore-line checkpoint */
int insline(int y) {                             /* insert a line = usave at index y */
    int i; int b; int k;
    if (nlines >= 110) { return 0; }
    i = nlines;
    while (i > y) { copyline(i, i - 1); i = i - 1; }
    b = y * 80; k = 0;
    while (usave[k] != 0) { line[b + k] = usave[k]; k = k + 1; }
    line[b + k] = 0;
    nlines = nlines + 1;
    return 0;
}
int undo() {
    int t; int b; int k;
    if (uop == 0) { gotoxy(24, 1); outs("nothing to undo"); clreol(); placecur(); return 0; }
    t = uop; uop = 0;                            /* single level */
    if (t == 1) {                                /* restore line[uy] = usave */
        b = uy * 80; k = 0;
        while (usave[k] != 0) { line[b + k] = usave[k]; k = k + 1; }
        line[b + k] = 0;
        cy = uy; cx = ux; clampx();
    } else if (t == 2) {                         /* undo an 'o': remove the opened line */
        cy = uy; delline();
    } else if (t == 3) {                         /* undo a 'dd': reinsert the line */
        insline(uy); cy = uy; cx = 0;
    }
    dirty = 1;
    scroll();
    redraw();
    return 0;
}

/* ---- search (literal substring, forward, wraps once) ----------------------- */
int matchat(int b, int j) {
    int m;
    m = 0;
    while (pat[m] != 0 && line[b + j + m] == pat[m]) { m = m + 1; }
    if (pat[m] == 0) { return 1; }
    return 0;
}
int findfrom(int sy, int sx) {                   /* first match at/after (sy,sx) */
    int i; int b; int j;
    i = sy;
    while (i < nlines) {
        b = i * 80;
        if (i == sy) { j = sx; } else { j = 0; }
        while (line[b + j] != 0) {
            if (matchat(b, j)) { cy = i; cx = j; return 1; }
            j = j + 1;
        }
        i = i + 1;
    }
    return 0;
}
int search() {                                   /* find pat after the cursor, wrap once */
    if (findfrom(cy, cx + 1)) { return 1; }
    if (findfrom(0, 0)) { return 1; }
    return 0;
}
int getpat() {                                   /* read a '/' pattern; 1 = entered */
    int k; int c;
    gotoxy(24, 1); outc('/'); clreol();
    k = 0;
    c = rawkey();
    while (c != 13 && c != 10) {
        if (c == 27) { return 0; }               /* Esc cancels */
        if (c == 8 || c == 127) { if (k > 0) { k = k - 1; outc(8); outc(' '); outc(8); } }
        else if (k < 38) { pat[k] = c; k = k + 1; outc(c); }
        c = rawkey();
    }
    pat[k] = 0;
    if (k > 0) { havepat = 1; }                  /* empty '/' repeats the last pattern */
    return 1;
}

int main() {
    char *a;
    int i;
    int k;
    int pend;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: VI name   modal VT100 screen editor (:wq to save+quit)");
        return 0;
    }
    abspath(path, a);                            /* relative name -> CWD-prefixed */

    load(path);
    mode = 0; dirty = 0; done = 0; pend = 0; uop = 0; havepat = 0;
    redraw();

    while (done == 0) {
        k = rawkey();
        if (mode == 1) {                          /* ---- INSERT ---- */
            if (k == 27) {
                mode = 0;
                if (cx > 0) { cx = cx - 1; }
                status(); placecur();
            } else if (k == 13 || k == 10) {
                uop = 0;                          /* a split can't be single-line-undone */
                splitline();
                redraw();
            } else if (k == 8 || k == 127) {
                if (cx > 0) { cx = cx - 1; delchar(); drawrow(cy - top); placecur(); }
            } else if (k >= 32 && k < 127) {
                inschar(k); drawrow(cy - top); placecur();
            }
        } else {                                  /* ---- NORMAL ---- */
            if (pend == 1) {
                pend = 0;
                if (k == 'd') { saveline(); uop = 3; uy = cy; delline(); redraw(); }
            } else if (k == 'h') { if (cx > 0) { cx = cx - 1; placecur(); } }
            else if (k == 'l') { if (cx < llen(cy) - 1) { cx = cx + 1; placecur(); } }
            else if (k == 'j') { if (cy < nlines - 1) { cy = cy + 1; clampx(); if (scroll()) { redraw(); } else { placecur(); } } }
            else if (k == 'k') { if (cy > 0) { cy = cy - 1; clampx(); if (scroll()) { redraw(); } else { placecur(); } } }
            else if (k == '0') { cx = 0; placecur(); }
            else if (k == '$') { cx = llen(cy); if (cx > 0) { cx = cx - 1; } placecur(); }
            else if (k == 'G') { cy = nlines - 1; clampx(); if (scroll()) { redraw(); } else { placecur(); } }
            else if (k == 'i') { snap1(); mode = 1; status(); placecur(); }
            else if (k == 'a') { snap1(); if (llen(cy) > 0) { cx = cx + 1; } clampx(); mode = 1; status(); placecur(); }
            else if (k == 'A') { snap1(); cx = llen(cy); mode = 1; status(); placecur(); }
            else if (k == 'o') { uop = 2; uy = cy + 1; opendown(); mode = 1; redraw(); }
            else if (k == 'x') { snap1(); delchar(); clampx(); drawrow(cy - top); placecur(); }
            else if (k == 'd') { pend = 1; }
            else if (k == 'u') { undo(); }
            else if (k == '/') {
                if (getpat() && havepat) {
                    if (search()) { redraw(); }
                    else { redraw(); gotoxy(24, 1); outs("pattern not found"); clreol(); placecur(); }
                } else { redraw(); }
            }
            else if (k == 'n') {
                if (havepat) {
                    if (search()) { redraw(); }
                    else { gotoxy(24, 1); outs("pattern not found"); clreol(); placecur(); }
                }
            }
            else if (k == ':') { docmd(); if (done == 0) { redraw(); } }
        }
    }
    clrscr();
    gotoxy(1, 1);
    return 0;
}
