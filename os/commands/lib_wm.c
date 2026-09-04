/* lib_wm.c -- the window manager core (//#use wm).
 *
 * Rung 2 of the window system: up to four windows with visibility,
 * z-order, focus, title-bar drag, CLOSE BOXES, and a Mac-style
 * press-drag-release MENU along the top of the screen. Clients must
 * also //#use abi and //#use ptr, define the GL port with //#define
 * GLDATA/GLSTAT (this library pokes them raw), and provide:
 *
 *   int wm_content(int i);   draw window i's content in LOCAL coords
 *                            (the library has already set the mapping)
 *   char *wm_title(int i);   the window's title string
 *
 * THE MECHANISM (rung 1's, now shared): each window's content draws
 * under its own WINDOW/VWPORT pair -- local coordinates, hardware
 * clip, occlusion by paint order. The library owns the chrome, the
 * painter's repaint, hit testing, the drag outline and the menu; the
 * app owns content and the event pump:
 *
 *   t = ptr_ev();
 *   if (t == 1) { r = wm_press(ptr_x, ptr_y); ... }
 *   else if (t == 2) { wm_dragm(ptr_x, ptr_y); }
 *   else if (t == 3) { wm_drop(ptr_x, ptr_y); }
 *
 * wm_press returns 0 miss, 1 handled (raise/drag-arm), 2 menu item
 * chosen (index in wm_msel), 3 a window closed (index in wm_closed).
 * The menu tracks its own press-drag-release inside wm_press, the
 * classic way: hold, slide to the item, let go.
 *
 * The menu bar owns the top 14 rows; windows clamp beneath it.
 */

/* ---- windows ---------------------------------------------------------------- */
int wm_n;                          /* how many windows exist (<= 4) */
int wmx[4]; int wmy[4];            /* bottom-left, window coords */
int wmw[4]; int wmh[4];            /* outer size */
int wmvis[4];                      /* 1 = shown */
int wmz[4];                        /* stacking, bottom first */

/* the app's one menu: a title and up to 6 items of 15 chars */
char *wm_mtitle;
char wm_mitems[96];                /* 6 x 16, NUL-padded rows */
int wm_mcount;

int wm_msel;                       /* wm_press result 2: chosen item */
int wm_closed;                     /* wm_press result 3: closed window */

int wm_dragw;                      /* 99 = none (p8cc compares are UNSIGNED:
                                      never a -1 sentinel) */
int wm_dgx; int wm_dgy;
int wm_dox; int wm_doy;

/* ---- GL (raw, like the clients) -------------------------------------------- */
int wgput(int v) {
    while (peek(GLSTAT) & 128) { }
    poke(GLDATA, v);
    return 0;
}
int wgw(int v) { wgput(v & 255); wgput((v / 256) & 255); return 0; }
int wpen(int c) {
    wgput(6); wgput((c >> 11) & 31); wgput((c >> 5) & 63); wgput(c & 31);
    return 0;
}
int wmode(int m) { wgput(235); wgput(m); return 0; }
int wfill(int f) { wgput(224); wgput(f); return 0; }
int wmov(int x, int y) { wgput(16); wgw(x); wgw(y); return 0; }
int wrect(int x, int y) { wgput(52); wgw(x); wgw(y); return 0; }

int wm_vall() {
    wgput(179); wgw(0); wgw(479); wgw(0); wgw(271);
    wgput(178); wgw(0); wgw(479); wgw(0); wgw(271);
    return 0;
}
/* the per-window content mapping: local 0..cw-1 x 0..ch-1, translated
 * and clipped by the card (VWPORT y is top-down device rows) */
int wm_vwin(int i) {
    int cw; int ch;
    cw = wmw[i] - 2; ch = wmh[i] - 15;
    wgput(179); wgw(0); wgw(cw - 1); wgw(0); wgw(ch - 1);
    wgput(178); wgw(wmx[i] + 1); wgw(wmx[i] + cw);
    wgw(271 - (wmy[i] + ch)); wgw(271 - (wmy[i] + 1));
    return 0;
}

/* stroke text at (x,y) under the CURRENT mapping */
int wm_text(int x, int y, char *s) {
    int n;
    n = 0;
    while (s[n] != 0) { n = n + 1; }
    if (n == 0) { return 0; }
    wgput(18); wgw(x); wgw(y); wgw(0);        /* MOVE3 x y 0 */
    wgput(128); wgput(n);
    while (*s) { wgput(*s); s = s + 1; }
    return 0;
}

/* ---- chrome ----------------------------------------------------------------- */
int wm_top() {                     /* the topmost VISIBLE window, or 99 */
    int i;
    i = wm_n;
    while (i) {
        i = i - 1;
        if (wmvis[wmz[i]]) { return wmz[i]; }
    }
    return 99;
}

int wm_chrome(int i, int focused) {
    wm_vall();
    wpen(0); wfill(1);                        /* opaque body */
    wmov(wmx[i], wmy[i]); wrect(wmx[i] + wmw[i] - 1, wmy[i] + wmh[i] - 1);
    if (focused) { wpen(65535); } else { wpen(33808); }
    wmov(wmx[i], wmy[i] + wmh[i] - 14);       /* title bar */
    wrect(wmx[i] + wmw[i] - 1, wmy[i] + wmh[i] - 1);
    wfill(0);
    wpen(65535);                              /* border */
    wmov(wmx[i], wmy[i]); wrect(wmx[i] + wmw[i] - 1, wmy[i] + wmh[i] - 1);
    wpen(0);                                  /* close box, on the bar */
    wmov(wmx[i] + 3, wmy[i] + wmh[i] - 12);
    wrect(wmx[i] + 11, wmy[i] + wmh[i] - 4);
    wm_text(wmx[i] + 16, wmy[i] + wmh[i] - 11, wm_title(i));
    return 0;
}

int wm_bar() {                     /* the menu bar: top 14 rows */
    wm_vall();
    wpen(65535); wfill(1);
    wmov(0, 258); wrect(479, 271);
    wfill(0);
    wpen(0);
    wm_text(8, 261, wm_mtitle);
    return 0;
}

int wm_repaint() {
    int i;
    wm_vall();
    wgput(7); wgput(6); wgput(12); wgput(9);  /* FLOOD: desktop */
    i = 0;
    while (i < wm_n) {
        if (wmvis[wmz[i]]) {
            wm_chrome(wmz[i], wmz[i] == wm_top());
            wm_vwin(wmz[i]);
            wm_content(wmz[i]);
        }
        i = i + 1;
    }
    wm_bar();
    wm_vall();
    return 0;
}

/* ---- stacking, hit tests ---------------------------------------------------- */
int wm_raise(int i) {
    int j; int k;
    if (wm_top() == i) { return 0; }
    j = 0; k = 0;
    while (j < wm_n) {                        /* remove i, keep order */
        if (wmz[j] != i) { wmz[k] = wmz[j]; k = k + 1; }
        j = j + 1;
    }
    wmz[wm_n - 1] = i;                        /* on top */
    wm_repaint();
    return 1;
}

int wm_in(int i, int x, int y) {
    if (wmvis[i] == 0) { return 0; }
    if (x < wmx[i] || x >= wmx[i] + wmw[i]) { return 0; }
    if (y < wmy[i] || y >= wmy[i] + wmh[i]) { return 0; }
    return 1;
}
int wm_hit(int x, int y) {                    /* topmost window at (x,y), 99 */
    int i;
    i = wm_n;
    while (i) {
        i = i - 1;
        if (wm_in(wmz[i], x, y)) { return wmz[i]; }
    }
    return 99;
}

int wm_clampx(int i, int x) {
    if (x > 30000) { return 0; }
    if (x > 480 - wmw[i]) { return 480 - wmw[i]; }
    return x;
}
int wm_clampy(int i, int y) {
    if (y > 30000) { return 0; }
    if (y > 258 - wmh[i]) { return 258 - wmh[i]; }   /* under the bar */
    return y;
}

/* ---- the drag outline (complement, self-inverse) ---------------------------- */
int wm_line(int i, int x, int y) {
    wmode(1);
    wmov(x, y); wrect(x + wmw[i] - 1, y + wmh[i] - 1);
    wmode(0);
    return 0;
}

/* ---- the menu: press-drag-release tracking ---------------------------------- */
int wm_mwidth() { return 110; }
int wm_mitem(int y) {                         /* dropdown item under wy, 99 */
    int top; int i;
    top = 258;
    i = 0;
    while (i < wm_mcount) {
        if (y <= top - 1 - i * 14 && y >= top - 14 - i * 14) { return i; }
        i = i + 1;
    }
    return 99;
}
int wm_mhl(int i) {                           /* highlight row i (complement) */
    if (i >= wm_mcount) { return 0; }
    wmode(1); wfill(1);
    wmov(4, 258 - 14 - i * 14); wrect(wm_mwidth() - 4, 257 - i * 14);
    wfill(0); wmode(0);
    return 0;
}
int wm_menu() {                               /* returns the item, or 99 */
    int i; int t; int sel; int ns;
    wm_vall();
    wpen(65535); wfill(1);                    /* the dropdown sheet */
    wmov(2, 258 - wm_mcount * 14 - 2); wrect(wm_mwidth(), 257);
    wfill(0);
    wpen(0);
    wmov(2, 258 - wm_mcount * 14 - 2); wrect(wm_mwidth(), 257);
    i = 0;
    while (i < wm_mcount) {
        wm_text(10, 258 - 11 - i * 14, wm_mitems + i * 16);
        i = i + 1;
    }
    sel = 99;
    t = 2;
    while (t == 2 || t == 1) {                /* until release */
        ns = wm_mitem(ptr_y);
        if (ptr_x > wm_mwidth()) { ns = 99; }
        if (ns != sel) {
            wm_mhl(sel); wm_mhl(ns);          /* move the highlight */
            sel = ns;
        }
        t = ptr_ev();
        if (t == 0) { t = 3; sel = 99; }      /* a key aborts */
    }
    wm_repaint();                             /* damage repair */
    return sel;
}

/* ---- the press/drag/release protocol ---------------------------------------- */
int wm_press(int x, int y) {
    int i;
    if (y >= 258) {                           /* the menu bar */
        if (x < wm_mwidth()) {
            wm_msel = wm_menu();
            if (wm_msel < wm_mcount) { return 2; }
        }
        return 1;
    }
    i = wm_hit(x, y);
    if (i >= wm_n) { return 0; }
    wm_raise(i);
    if (y >= wmy[i] + wmh[i] - 14) {          /* the title bar */
        if (x >= wmx[i] + 3 && x <= wmx[i] + 11) {   /* the close box */
            wmvis[i] = 0;
            wm_closed = i;
            wm_repaint();
            return 3;
        }
        wm_dragw = i;
        wm_dgx = x - wmx[i]; wm_dgy = y - wmy[i];
        wm_dox = wmx[i]; wm_doy = wmy[i];
        wm_line(i, wm_dox, wm_doy);
    }
    return 1;
}

int wm_dragm(int x, int y) {
    if (wm_dragw >= wm_n) { return 0; }
    wm_line(wm_dragw, wm_dox, wm_doy);
    wm_dox = wm_clampx(wm_dragw, x - wm_dgx);
    wm_doy = wm_clampy(wm_dragw, y - wm_dgy);
    wm_line(wm_dragw, wm_dox, wm_doy);
    return 0;
}

int wm_drop(int x, int y) {
    if (wm_dragw >= wm_n) { return 0; }
    wm_line(wm_dragw, wm_dox, wm_doy);
    wmx[wm_dragw] = wm_dox; wmy[wm_dragw] = wm_doy;
    wm_dragw = 99;
    wm_repaint();
    return 0;
}

int wm_init() {
    wm_dragw = 99; wm_msel = 99; wm_closed = 99;
    return 0;
}
