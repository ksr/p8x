/* desk.c -- the window system demo (rungs 2+3 of the GUI ladder).
 *
 * Four windows under lib_wm: SHAPES (content recorded ONCE into a
 * card-resident command list -- every repaint is CLRUN, two wire
 * bytes), TERM (a small terminal: typed input under focus), FILES (a
 * directory browser: click or arrow to select, ENTER or the OPEN
 * menu item to open -- directories navigate, .P8I files open in...)
 * and VIEW (a picture window: the image BLITs straight from its file
 * into window-local coordinates each repaint). Close boxes, a
 * Mac-style press-drag-release menu, per-window hardware clipping,
 * painter's repaint -- see man desk.
 *
 * Keys: TAB cycles windows; arrows move the top window -- except a
 * focused FILES, where they move the SELECTION and ENTER opens;
 * printable keys type into a focused TERM; Ctrl-D quits.
 */

//#use abi

//#define GLDATA 0xFF50
//#define GLSTAT 0xFF51
//#define GLID   0xFF54

//#use ptr
//#use wm
//#use dirent

/* the TERM window's text: 5 history lines + the input line, 28 cols */
char tln[168];
int tcur;

/* the FILES window: current path, entries, selection */
char cpath[64];
char fnam[130];                    /* 10 entries x 13 (NUL-terminated) */
char fdir[10];
int fcnt; int fsel;

/* the VIEW window: the open picture */
char vpath[48];
int vw; int vh;

char *wm_title(int i) {
    if (i == 0) { return "SHAPES"; }
    if (i == 1) { return "TERM"; }
    if (i == 2) { return cpath; }
    return "VIEW";
}

int drawview();

int wm_content(int i) {
    int r; int ch;
    ch = wmh[i] - 15;
    if (i == 0) {
        wgput(114); wgput(30);                /* CLRUN 30: the recorded scene */
        return 0;
    }
    if (i == 1) {
        wpen(2016);
        r = 0;
        while (r < 5) {
            wm_text(3, ch - 13 - r * 13, tln + (4 - r) * 28);
            r = r + 1;
        }
        wpen(65535);
        wm_text(3, 4, tln + 140);
        return 0;
    }
    if (i == 2) {                             /* FILES: the listing */
        r = 0;
        while (r < fcnt) {
            if (r == fsel) { wpen(65504); } else { wpen(65535); }
            if (fdir[r]) { wpen(2047); }
            if (r == fsel && fdir[r]) { wpen(65504); }
            wm_text(4, ch - 13 - r * 13, fnam + r * 13);
            r = r + 1;
        }
        if (fsel < fcnt) {                    /* the selection tick */
            wpen(65504);
            wmov(1, ch - 9 - fsel * 13); wgput(40); wgw(3); wgw(ch - 9 - fsel * 13);
        }
        return 0;
    }
    return drawview();                        /* VIEW */
}

/* record SHAPES' scene into card list 30 -- local coords, no mapping
 * verbs inside, so it replays under WHEREVER the window sits */
int rec_shapes() {
    int cw; int ch;
    cw = wmw[0] - 2; ch = wmh[0] - 15;
    wgput(112); wgput(30);                    /* CLBEG 30 */
    wpen(63488);
    wmov(10, 10); wrect(cw - 10, ch - 10);    /* the red frame */
    wpen(65504);
    wmov(cw - 30, ch - 20); wrect(cw + 60, ch + 60); /* RECT overrun:
                                                 clipped by the card */
    wgput(113);                               /* CLEND */
    return 0;
}

int tclear() {
    int i;
    i = 0;
    while (i < 168) { tln[i] = 0; i = i + 1; }
    tln[140] = '>'; tln[141] = ' '; tcur = 2;
    return 0;
}
int tscroll() {
    int i;
    i = 0;
    while (i < 4 * 28) { tln[i] = tln[i + 28]; i = i + 1; }
    i = 0;
    while (i < 28) { tln[4 * 28 + i] = tln[5 * 28 + i]; i = i + 1; }
    tln[140] = '>'; tln[141] = ' '; tcur = 2;
    return 0;
}
int tkey(int k) {
    if (k == 13 || k == 10) { tscroll(); wm_repaint(); return 0; }
    if (k == 8 || k == 127) {
        if (tcur > 2) { tcur = tcur - 1; tln[140 + tcur] = 0; wm_repaint(); }
        return 0;
    }
    if (k >= 32 && k < 127 && tcur < 27) {
        tln[140 + tcur] = k; tln[141 + tcur] = 0; tcur = tcur + 1;
        wm_repaint();
    }
    return 0;
}

/* ---- the FILES browser ------------------------------------------------------ */
int tprint(char *s) {                         /* a line into TERM's history */
    int i;
    tscroll();
    i = 0;
    while (s[i] != 0 && i < 27) { tln[4 * 28 + i] = s[i]; i = i + 1; }
    tln[4 * 28 + i] = 0;
    return 0;
}

int fscan() {                                 /* read cpath's entries */
    int r; int j; int k;
    fcnt = 0; fsel = 0;
    r = bios(FOPENDIR, cpath, 0);
    if (r & 256) { return 1; }
    r = bios(FNEXT, 0, 0);
    while ((r & 256) == 0 && fcnt < 10) {
        de_read();
        /* keep real files and dirs whose name STARTS PRINTABLE -- this
         * skips '.', deleted slots ($E5 first byte: FNEXT yields them,
         * and TEXT would draw an undefined glyph as a silent skip, a
         * phantom empty row) and the volume slot -- but keeps '..' */
        j = de[0] & 255;
        if ((de_isfile() || de_isdir()) && j >= 33 && j <= 126 &&
            (de_isdot() == 0 || (de[1] & 255) == '.')) {
            j = 0; k = fcnt * 13;
            while (j < 12) {
                if ((de[j] & 255) > 32) { fnam[k] = de[j]; k = k + 1; }
                j = j + 1;
            }
            fnam[k] = 0;
            if (k > fcnt * 13) {              /* a non-empty name only */
                fdir[fcnt] = de_isdir();
                fcnt = fcnt + 1;
            }
        }
        r = bios(FNEXT, 0, 0);
    }
    return 0;
}

int pjoin(char *out, char *dir, char *leaf) { /* out = dir + "/" + leaf */
    int i; int j;
    i = 0;
    while (dir[i] != 0) { out[i] = dir[i]; i = i + 1; }
    if (i > 1) { out[i] = '/'; i = i + 1; }   /* "/" needs no extra slash */
    j = 0;
    while (leaf[j] != 0) { out[i] = leaf[j]; i = i + 1; j = j + 1; }
    out[i] = 0;
    return 0;
}

int ftype(char *s) {                          /* 1 = .P8I, 2 = .BIN, else 0
                                                 (case-blind: &95 folds) */
    int n;
    n = 0;
    while (s[n] != 0) { n = n + 1; }
    if (n < 4) { return 0; }
    if (s[n-4] != '.') { return 0; }
    if ((s[n-3] & 95) == 'P' && s[n-2] == '8' && (s[n-1] & 95) == 'I') { return 1; }
    if ((s[n-3] & 95) == 'B' && (s[n-2] & 95) == 'I' && (s[n-1] & 95) == 'N') { return 2; }
    return 0;
}

/* the VIEW window's content: header-skip, then one BLIT per row, the
 * file bytes streamed verbatim -- anchored in LOCAL coords, so the
 * picture rides wherever the window is dragged */
int drawview() {
    int py; int n; int r;
    bios(FRESOLVE, vpath, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { return 0; }
    py = 0;
    while (py < 10) { bios(FGETB, 0, 0); py = py + 1; }  /* the header */
    py = 0;
    while (py < vh) {
        wgput(100);                           /* BLIT x y w 1 */
        wgw(0); wgw(vh - 1 - py);
        wgw(vw); wgw(1);
        n = vw + vw;
        while (n) {
            r = bios(FGETB, 0, 0);
            if (r & 256) { wgput(0); } else { wgput(r & 255); }
            n = n - 1;
        }
        py = py + 1;
    }
    return 0;
}

int fopen_sel() {                             /* ENTER/OPEN on the selection */
    int r; int w2; int h2;
    if (fsel >= fcnt) { return 0; }
    if (fdir[fsel]) {                         /* navigate */
        if (fnam[fsel * 13] == '.') {         /* ".." -> strip a component */
            r = 0;
            while (cpath[r] != 0) { r = r + 1; }
            while (r > 1 && cpath[r] != '/') { r = r - 1; }
            if (r == 0) { r = 1; }
            cpath[r] = 0;
            if (cpath[1] == 0) { cpath[0] = '/'; cpath[1] = 0; }
        } else {                              /* vpath doubles as scratch */
            pjoin(vpath, cpath, fnam + fsel * 13);
            r = 0;
            while (vpath[r] != 0) { cpath[r] = vpath[r]; r = r + 1; }
            cpath[r] = 0;
        }
        fscan();
        wm_repaint();
        return 0;
    }
    r = ftype(fnam + fsel * 13);
    if (r == 2) {                             /* a program: BECOME it, the
                                                 System-1 way -- SYS_EXEC
                                                 loads it over this very
                                                 code; "-d" asks it to
                                                 chain back to desk */
        pjoin(vpath, cpath, fnam + fsel * 13);
        w2 = 0;
        while (vpath[w2] != 0) { w2 = w2 + 1; }
        vpath[w2] = ' '; vpath[w2+1] = '-'; vpath[w2+2] = 'd'; vpath[w2+3] = 0;
        ptr_done();                           /* the terminal outlives us */
        bios(SYS_EXEC, vpath, 0);
        ptr_init();                           /* only reached on failure */
        tprint("?EXEC");
        wm_repaint();
        return 0;
    }
    if (r == 0) {
        tprint("NO VIEWER");
        wm_repaint();
        return 0;
    }
    pjoin(vpath, cpath, fnam + fsel * 13);
    bios(FRESOLVE, vpath, 0);                 /* read the header for size */
    if (bios(FOPEN, RDBUF, 0) & 256) { tprint("?NO FILE"); wm_repaint(); return 0; }
    bios(FGETB, 0, 0); bios(FGETB, 0, 0);     /* P 8 */
    bios(FGETB, 0, 0); bios(FGETB, 0, 0);     /* I ver */
    w2 = (bios(FGETB, 0, 0) & 255); w2 = w2 + (bios(FGETB, 0, 0) & 255) * 256;
    h2 = (bios(FGETB, 0, 0) & 255); h2 = h2 + (bios(FGETB, 0, 0) & 255) * 256;
    if (w2 == 0 || h2 == 0 || w2 > 456 || h2 > 240) {
        tprint("BAD P8I");
        wm_repaint();
        return 0;
    }
    vw = w2; vh = h2;
    wmw[3] = w2 + 2; if (wmw[3] < 70) { wmw[3] = 70; }
    wmh[3] = h2 + 15;
    wmx[3] = wm_clampx(3, wmx[3]); wmy[3] = wm_clampy(3, wmy[3]);
    wmvis[3] = 1;
    wm_raise(3);
    wm_repaint();
    return 0;
}

/* arrows walk the FILES selection (windows move by mouse, as they should) */
int akey(int k) {
    if (wm_top() != 2) { return 0; }
    if (k == 128 && fsel) { fsel = fsel - 1; wm_repaint(); }
    if (k == 129 && fsel + 1 < fcnt) { fsel = fsel + 1; wm_repaint(); }
    return 0;
}

int mcopy(int row, char *s) {
    int i;
    i = 0;
    while (s[i] != 0) { wm_mitems[row * 16 + i] = s[i]; i = i + 1; }
    wm_mitems[row * 16 + i] = 0;
    return 0;
}

int main() {
    int t; int k; int going; int i;
    if (peek(GLID) != 71) { puts("?No display"); return 1; }
    wm_init();
    wm_n = 4;
    wmx[0] = 40;  wmy[0] = 40; wmw[0] = 210; wmh[0] = 150; wmvis[0] = 1;
    wmx[1] = 190; wmy[1] = 90; wmw[1] = 240; wmh[1] = 140; wmvis[1] = 1;
    wmx[2] = 336; wmy[2] = 30; wmw[2] = 138; wmh[2] = 210; wmvis[2] = 1;
    wmx[3] = 20;  wmy[3] = 20; wmw[3] = 100; wmh[3] = 100; wmvis[3] = 0;
    wmz[0] = 0; wmz[1] = 2; wmz[2] = 1; wmz[3] = 3;   /* TERM on top */
    tclear();
    cpath[0] = '/'; cpath[1] = 0;
    fscan();
    wm_mtitle = "DESK";
    wm_mcount = 2;
    mcopy(0, "NEW TERM");
    mcopy(1, "QUIT");

    wgput(4);                                 /* RESETF                    */
    wgput(176); wgw(0);                       /* PROJCT 0 (2D text)        */
    wgput(144);                               /* MDIDEN                    */
    wgput(129); wgw(256);                     /* TSIZE 1x                  */
    rec_shapes();
    wm_repaint();
    outs("DESK (man desk)");
    outc(13); outc(10);
    ptr_init();

    going = 1;
    while (going) {
        t = ptr_ev();
        if (t == 1) {
            k = wm_press(ptr_x, ptr_y);
            if (k == 2) {                     /* a menu choice */
                if (wm_msel == 0) {           /* NEW TERM */
                    tclear(); wmvis[1] = 1; wm_raise(1); wm_repaint();
                }
                if (wm_msel == 1) { going = 0; }
            } else if (k == 1 && wm_top() == 2) {
                /* a click inside FILES content selects its row */
                i = wmy[2] + wmh[2] - 15;     /* content top, screen coords */
                if (ptr_y < i && ptr_x > wmx[2] && ptr_x < wmx[2] + wmw[2]) {
                    i = (i - 1 - ptr_y) / 13;
                    if (i < fcnt) { fsel = i; wm_repaint(); }
                }
            }
        } else if (t == 2) { wm_dragm(ptr_x, ptr_y); }
        else if (t == 3) { wm_drop(ptr_x, ptr_y); }
        else if (t == 0) {
            k = ptr_key;
            if (k == 4) { going = 0; }
            else if (k == 9) {                /* TAB: raise the bottom one */
                i = 0;
                while (i < wm_n) {
                    if (wmvis[wmz[i]] && wmz[i] != wm_top()) {
                        wm_raise(wmz[i]); i = wm_n;
                    }
                    i = i + 1;
                }
            }
            else if (k >= 128 && k <= 131) { akey(k); }
            else if ((k == 13 || k == 10) && wm_top() == 2) { fopen_sel(); }
            else if (wm_top() == 1) { tkey(k); }
        }
    }
    wgput(116); wgput(30);                    /* CLDEL 30: tidy the card */
    ptr_done();
    while (peek(GLSTAT) & 64) { }
    outc(13); outc(10); puts("bye");
    return 0;
}
