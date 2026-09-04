/* desk.c -- rung 1 of the window system: overlapping windows on the
 * graphics card, dragged with the mouse, repainted by the painter's
 * algorithm, each hardware-clipped by the card itself.
 *
 * THE MECHANISM (the whole point of the rung): a window's content is
 * drawn in LOCAL coordinates under a per-window WINDOW/VWPORT pair --
 * WINDOW 0..w-1 x 0..h-1 declares the local extent, VWPORT places it
 * on screen, and because the extents match, the map is a pure
 * TRANSLATION with the window edge as a hardware CLIP. Content cannot
 * escape its window, occlusion is just paint order (bottom to top),
 * and the CPU keeps only rectangles and a z-order.
 *
 * Two windows prove it: SHAPES (primitives that deliberately overrun
 * the window, to show the clip) and TERM -- a little terminal: typed
 * characters echo into its input line when it has FOCUS, ENTER
 * scrolls. Text is the card's own stroke TEXT, drawn in local
 * coordinates like everything else (the 3D pipeline clips through
 * the same window).
 *
 * Keys: TAB raise/focus the other window; arrows move the focused
 * window; printable keys type into a focused TERM; ENTER commits the
 * line; Ctrl-D quits. Mouse: press a title bar and drag -- a
 * complement-mode outline follows (the classic outline drag), release
 * places the window; press anywhere in a window to raise it.
 */

//#use abi
//#use ptr

//#define GLDATA 0xFF50
//#define GLSTAT 0xFF51
//#define GLID   0xFF54

/* ---- the two windows (parallel arrays; p8cc has no structs) --------------- */
int wx[2]; int wy[2];              /* bottom-left corner, window coords */
int ww[2]; int wh[2];              /* outer size (title bar included) */
int wkind[2];                      /* 0 = SHAPES, 1 = TERM */
int zord[2];                       /* stacking, bottom first; zord[1] = focus */

/* the TERM window's text: 5 history lines + the input line, 28 cols */
char tln[168];                     /* 6 x 28 */
int tcur;                          /* input cursor within line 5 */

int dragw;                         /* window being dragged, 99 = none
                                      (p8cc compares are UNSIGNED: never
                                      use a -1 sentinel with >= 0) */
int dgx; int dgy;                  /* drag grab offset within the window */
int dox; int doy;                  /* current outline position */

/* ---- GL emission ----------------------------------------------------------- */
int gput(int v) {
    while (peek(GLSTAT) & 128) { }
    poke(GLDATA, v);
    return 0;
}
int gw(int v) { gput(v & 255); gput((v / 256) & 255); return 0; }
int gwait() { while (peek(GLSTAT) & 64) { } return 0; }
int pen(int c) {
    gput(6); gput((c >> 11) & 31); gput((c >> 5) & 63); gput(c & 31);
    return 0;
}
int mode(int m) { gput(235); gput(m); return 0; }
int fillm(int f) { gput(224); gput(f); return 0; }
int mov(int x, int y) { gput(16); gw(x); gw(y); return 0; }
int rect(int x, int y) { gput(52); gw(x); gw(y); return 0; }
int draw(int x, int y) { gput(40); gw(x); gw(y); return 0; }

/* the screen mapping (identity) and the per-window one (translation +
 * clip): VWPORT y is top-down device rows, so window wy w maps to row
 * 271-w exactly when the pairs move together -- the paint lesson. */
int vp_all() {
    gput(179); gw(0); gw(479); gw(0); gw(271);
    gput(178); gw(0); gw(479); gw(0); gw(271);
    return 0;
}
int vp_win(int i, int cw, int ch) {           /* content-local mapping */
    gput(179); gw(0); gw(cw - 1); gw(0); gw(ch - 1);
    gput(178); gw(wx[i]); gw(wx[i] + cw - 1);
    gw(271 - (wy[i] + ch - 1)); gw(271 - wy[i]);
    return 0;
}

/* stroke text at (x,y) in the CURRENT mapping's coordinates */
int text(int x, int y, char *s) {
    int n;
    n = 0;
    while (s[n] != 0) { n = n + 1; }
    if (n == 0) { return 0; }
    gput(18); gw(x); gw(y); gw(0);            /* MOVE3 x y 0 */
    gput(128); gput(n);                       /* TEXT n ch.. */
    while (*s) { gput(*s); s = s + 1; }
    return 0;
}

/* ---- the window chrome and contents ---------------------------------------- */
int chrome(int i, int focused) {
    vp_all();
    pen(0); fillm(1);                         /* opaque body: black */
    mov(wx[i], wy[i]); rect(wx[i] + ww[i] - 1, wy[i] + wh[i] - 1);
    if (focused) { pen(65535); } else { pen(33808); }   /* title bar */
    mov(wx[i], wy[i] + wh[i] - 14); rect(wx[i] + ww[i] - 1, wy[i] + wh[i] - 1);
    fillm(0);
    pen(65535);                               /* border */
    mov(wx[i], wy[i]); rect(wx[i] + ww[i] - 1, wy[i] + wh[i] - 1);
    pen(0);                                   /* title, on the bar */
    if (wkind[i] == 0) { text(wx[i] + 5, wy[i] + wh[i] - 11, "SHAPES"); }
    else { text(wx[i] + 5, wy[i] + wh[i] - 11, "TERM"); }
    return 0;
}

int content(int i) {
    int cw; int ch; int r;
    cw = ww[i] - 2; ch = wh[i] - 15;          /* inside border + bar */
    gput(179); gw(0); gw(cw - 1); gw(0); gw(ch - 1);
    gput(178); gw(wx[i] + 1); gw(wx[i] + cw);
    gw(271 - (wy[i] + ch)); gw(271 - (wy[i] + 1));
    if (wkind[i] == 0) {                      /* SHAPES: overrun on purpose */
        pen(63488);
        mov(10, 10); rect(cw - 10, ch - 10);
        pen(2016); fillm(1);
        mov(30, 25); gput(56); gw(18);        /* filled CIRCLE (kept inside:
                                                 curves clip at the SCREEN,
                                                 not the window -- man gl) */
        fillm(0);
        pen(2047);
        mov(0, 0); draw(300, 300);            /* line clips at the window */
        pen(65504);
        mov(cw - 30, ch - 20); rect(cw + 60, ch + 60);  /* RECT overruns:
                                                 clipped by the card */
    } else {                                  /* TERM: 5 history + input */
        pen(2016);
        r = 0;
        while (r < 5) {
            text(3, ch - 13 - r * 13, tln + (4 - r) * 28);
            r = r + 1;
        }
        pen(65535);
        text(3, 4, tln + 140);                /* the input line, "> ..." */
    }
    return 0;
}

int repaint() {
    int i;
    vp_all();
    gput(7); gput(6); gput(12); gput(9);      /* FLOOD: the desktop grey */
    i = 0;
    while (i < 2) {
        chrome(zord[i], i == 1);
        content(zord[i]);
        i = i + 1;
    }
    vp_all();
    return 0;
}

/* ---- drag outline (complement mode, self-inverse) -------------------------- */
int outline(int i, int x, int y) {
    mode(1);
    mov(x, y); rect(x + ww[i] - 1, y + wh[i] - 1);
    mode(0);
    return 0;
}

int clampw(int i, int x) {
    if (x > 30000) { return 0; }              /* wrapped negative (unsigned) */
    if (x > 480 - ww[i]) { return 480 - ww[i]; }
    return x;
}
int clamph(int i, int y) {
    if (y > 30000) { return 0; }
    if (y > 272 - wh[i]) { return 272 - wh[i]; }
    return y;
}

/* ---- window hit tests and stacking ----------------------------------------- */
int inwin(int i, int x, int y) {
    if (x < wx[i] || x >= wx[i] + ww[i]) { return 0; }
    if (y < wy[i] || y >= wy[i] + wh[i]) { return 0; }
    return 1;
}
int intitle(int i, int x, int y) {
    if (inwin(i, x, y) == 0) { return 0; }
    if (y >= wy[i] + wh[i] - 14) { return 1; }
    return 0;
}
int raise_w(int i) {
    if (zord[1] == i) { return 0; }
    zord[0] = zord[1]; zord[1] = i;
    repaint();
    return 1;
}

/* ---- the terminal ----------------------------------------------------------- */
int tscroll() {
    int i;
    i = 0;
    while (i < 4 * 28) { tln[i] = tln[i + 28]; i = i + 1; }
    i = 0;                                    /* input -> history line 4 */
    while (i < 28) { tln[4 * 28 + i] = tln[5 * 28 + i]; i = i + 1; }
    tln[140] = '>'; tln[141] = ' '; tln[142] = 0;
    tcur = 2;
    return 0;
}
int tkey(int k) {
    if (k == 13 || k == 10) { tscroll(); repaint(); return 0; }
    if (k == 8 || k == 127) {
        if (tcur > 2) { tcur = tcur - 1; tln[140 + tcur] = 0; repaint(); }
        return 0;
    }
    if (k >= 32 && k < 127 && tcur < 27) {
        tln[140 + tcur] = k; tln[141 + tcur] = 0; tcur = tcur + 1;
        repaint();
    }
    return 0;
}

int main() {
    int t; int k; int going; int i;
    if (peek(GLID) != 71) { puts("?No display"); return 1; }
    wx[0] = 40;  wy[0] = 40;  ww[0] = 210; wh[0] = 150; wkind[0] = 0;
    wx[1] = 190; wy[1] = 90;  ww[1] = 240; wh[1] = 140; wkind[1] = 1;
    zord[0] = 0; zord[1] = 1;                 /* TERM on top, focused */
    i = 0;
    while (i < 168) { tln[i] = 0; i = i + 1; }
    tln[140] = '>'; tln[141] = ' '; tcur = 2;
    dragw = 99;

    gput(4);                                  /* RESETF: known camera...   */
    gput(176); gw(0);                         /* ...then PROJCT 0 (ortho)  */
    gput(144);                                /* MDIDEN */
    gput(129); gw(256);                       /* TSIZE 1x */
    repaint();
    outs("DESK - drag title bars; TAB focus, type into TERM, ^D quits");
    outc(13); outc(10);
    ptr_init();

    going = 1;
    while (going) {
        t = ptr_ev();
        if (t == 1) {                         /* press */
            i = 99;
            if (inwin(zord[1], ptr_x, ptr_y)) { i = zord[1]; }
            else if (inwin(zord[0], ptr_x, ptr_y)) { i = zord[0]; }
            if (i < 2) {
                raise_w(i);
                if (intitle(i, ptr_x, ptr_y)) {
                    dragw = i;
                    dgx = ptr_x - wx[i]; dgy = ptr_y - wy[i];
                    dox = wx[i]; doy = wy[i];
                    outline(i, dox, doy);
                }
            }
        } else if (t == 2) {                  /* drag */
            if (dragw < 2) {
                outline(dragw, dox, doy);
                dox = clampw(dragw, ptr_x - dgx);
                doy = clamph(dragw, ptr_y - dgy);
                outline(dragw, dox, doy);
            }
        } else if (t == 3) {                  /* release */
            if (dragw >= 0) {
                outline(dragw, dox, doy);
                wx[dragw] = dox; wy[dragw] = doy;
                dragw = 99;
                repaint();
            }
        } else if (t == 0) {
            k = ptr_key;
            if (k == 4) { going = 0; }        /* Ctrl-D */
            else if (k == 9) { raise_w(zord[0]); }      /* TAB */
            else if (k == 128) { wy[zord[1]] = clamph(zord[1], wy[zord[1]] + 8); repaint(); }
            else if (k == 129) { wy[zord[1]] = clamph(zord[1], wy[zord[1]] - 8); repaint(); }
            else if (k == 130) { wx[zord[1]] = clampw(zord[1], wx[zord[1]] + 8); repaint(); }
            else if (k == 131) { wx[zord[1]] = clampw(zord[1], wx[zord[1]] - 8); repaint(); }
            else if (wkind[zord[1]] == 1) { tkey(k); }
        }
    }
    ptr_done();
    gwait();
    outc(13); outc(10); puts("bye");
    return 0;
}
