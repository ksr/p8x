/* desk.c -- rung 2 of the window system: the lib_wm demo.
 *
 * Windows with close boxes, a Mac-style press-drag-release MENU, and
 * one genuinely retro optimization: the SHAPES window's content is
 * recorded ONCE into a card-resident command list (CLBEG/CLEND), so
 * every repaint replays it for TWO wire bytes (CLRUN n) -- the scene
 * lives on the card, the CPU keeps only geometry. The TERM window
 * stays immediate (its text changes; and TEXT cannot be recorded --
 * the documented list limitation).
 *
 * The window machinery -- chrome, painter's repaint, per-window
 * hardware clip, drag outline, menu tracking, close boxes -- is
 * lib_wm (//#use wm); events are lib_ptr (//#use ptr): keyboard and
 * xterm-SGR mouse through the console.
 *
 * Keys: TAB raises the next window; arrows move the top window;
 * printable keys type into a focused TERM (ENTER scrolls, backspace
 * erases); Ctrl-D quits. Mouse: drag title bars; click the little
 * box on a title bar to CLOSE; press DESK in the menu bar and slide:
 * NEW TERM reopens a fresh terminal, CLOSE TOP closes the focused
 * window, QUIT quits.
 */

//#use abi

//#define GLDATA 0xFF50
//#define GLSTAT 0xFF51
//#define GLID   0xFF54

//#use ptr
//#use wm

/* the TERM window's text: 5 history lines + the input line, 28 cols */
char tln[168];
int tcur;

char *wm_title(int i) {
    if (i == 0) { return "SHAPES"; }
    return "TERM";
}

int wm_content(int i) {
    int r; int ch;
    if (i == 0) {
        wgput(114); wgput(30);                /* CLRUN 30: the recorded scene */
        return 0;
    }
    ch = wmh[1] - 15;
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

/* record SHAPES' scene into card list 30 -- local coords, no mapping
 * verbs inside, so it replays under WHEREVER the window sits */
int rec_shapes() {
    int cw; int ch;
    cw = wmw[0] - 2; ch = wmh[0] - 15;
    wgput(112); wgput(30);                    /* CLBEG 30 */
    wpen(63488);
    wmov(10, 10); wrect(cw - 10, ch - 10);
    wpen(2016); wfill(1);
    wmov(30, 25); wgput(56); wgw(18);         /* filled CIRCLE (kept inside:
                                                 curves clip at the SCREEN) */
    wfill(0);
    wpen(2047);
    wmov(0, 0); wgput(40); wgw(300); wgw(300);   /* line: clips at the window */
    wpen(65504);
    wmov(cw - 30, ch - 20); wrect(cw + 60, ch + 60); /* RECT overrun: clipped */
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
    wm_n = 2;
    wmx[0] = 40;  wmy[0] = 40; wmw[0] = 210; wmh[0] = 150; wmvis[0] = 1;
    wmx[1] = 190; wmy[1] = 90; wmw[1] = 240; wmh[1] = 140; wmvis[1] = 1;
    wmz[0] = 0; wmz[1] = 1;                   /* TERM on top */
    tclear();
    wm_mtitle = "DESK";
    wm_mcount = 3;
    mcopy(0, "NEW TERM");
    mcopy(1, "CLOSE TOP");
    mcopy(2, "QUIT");

    wgput(4);                                 /* RESETF                    */
    wgput(176); wgw(0);                       /* PROJCT 0 (2D text)        */
    wgput(144);                               /* MDIDEN                    */
    wgput(129); wgw(256);                     /* TSIZE 1x                  */
    rec_shapes();
    wm_repaint();
    outs("DESK - drag titles; close boxes; DESK menu; TAB, ^D quits");
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
                if (wm_msel == 1) {           /* CLOSE TOP */
                    i = wm_top();
                    if (i < wm_n) { wmvis[i] = 0; wm_repaint(); }
                }
                if (wm_msel == 2) { going = 0; }
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
            else if (k == 128) { i = wm_top(); if (i < wm_n) { wmy[i] = wm_clampy(i, wmy[i] + 8); wm_repaint(); } }
            else if (k == 129) { i = wm_top(); if (i < wm_n) { wmy[i] = wm_clampy(i, wmy[i] - 8); wm_repaint(); } }
            else if (k == 130) { i = wm_top(); if (i < wm_n) { wmx[i] = wm_clampx(i, wmx[i] + 8); wm_repaint(); } }
            else if (k == 131) { i = wm_top(); if (i < wm_n) { wmx[i] = wm_clampx(i, wmx[i] - 8); wm_repaint(); } }
            else if (wm_top() == 1) { tkey(k); }
        }
    }
    wgput(116); wgput(30);                    /* CLDEL 30: tidy the card */
    ptr_done();
    while (peek(GLSTAT) & 64) { }
    outc(13); outc(10); puts("bye");
    return 0;
}
