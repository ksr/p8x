/* lib_ptr.c -- console keyboard + pointer events (//#use ptr).
 *
 * One event source for interactive graphics programs: keys and the
 * MOUSE, both arriving on the raw console (CONIN). The mouse comes as
 * xterm SGR reports -- ptr_init() enables tracking (ESC[?1002h +
 * ESC[?1006h) and asks the terminal its size (ESC[18t) so cell
 * positions map onto the 480x272 panel; a terminal that answers
 * neither still delivers every key, mapped 80x24. Clients MUST also
 * `//#use abi` (CONIN/CONOUT/CONST) and call ptr_done() on exit.
 *
 * ptr_ev() blocks for the next event and returns its type:
 *   0 key      ptr_key = the character; arrows arrive as 128..131
 *              (up down right left), other CSI reports are swallowed
 *   1 press    ptr_x/ptr_y = panel coords (window sense, y UP)
 *   2 drag     (button held)
 *   3 release
 *   4 right-click press
 * Wheel and other buttons are ignored. The scripted-input trap is
 * handled: the size query never eats a real keystroke (a non-ESC
 * first byte is pushed back), so `p8xemu -i` sessions can drive a
 * client -- mouse included -- as printf'd bytes.
 */

int ptr_key; int ptr_x; int ptr_y;

int _pcols; int _prows;            /* terminal geometry */
int _pxs; int _pxr; int _pys; int _pyr;   /* cell->panel step/rem split:
                                             (mx-1)*480 overflows 16 bits */
int _ppush;                        /* one-key pushback */
int _pseq;                         /* a swallowed "ESC [" awaits: its
                                      first body byte is in _pseqb */
int _pseqb;

int outc(int c) { bios(CONOUT, 0, c & 255); return 0; }
int outs(char *s) { int i; i = 0; while (s[i] != 0) { outc(s[i]); i = i + 1; } return 0; }
int rawkey() {
    int k;
    if (_ppush) { k = _ppush; _ppush = 0; return k; }
    return bios(CONIN, 0, 0) & 255;
}
int keyrdy() { return bios(CONST, 0, 0) & 255; }         /* no wait */

int _pmapin() {
    _pxs = 480 / _pcols; _pxr = 480 - _pxs * _pcols;
    _pys = 272 / _prows; _pyr = 272 - _pys * _prows;
    return 0;
}
int _pmapx(int mx) {
    mx = mx - 1;
    return mx * _pxs + (mx * _pxr) / _pcols;
}
int _pmapwy(int my) {
    my = my - 1;
    return 271 - (my * _pys + (my * _pyr) / _prows);
}

/* ESC[18t -> ESC[8;rows;colst, CONST-probed with a bounded spin, and
 * STRICT at every step: a non-ESC first byte is a real keystroke
 * (pushed back); an ESC[ opening some OTHER sequence -- a scripted
 * mouse report, say -- is handed to ptr_ev() intact via _pseq. */
int _ptsize() {
    int i; int k; int st; int b; int c;
    _pcols = 80; _prows = 24;
    outc(27); outs("[18t");
    i = 0;
    while (i < 20000 && keyrdy() == 0) { i = i + 1; }
    if (keyrdy() == 0) { return 0; }
    k = rawkey();
    if (k != 27) { _ppush = k; return 0; }
    k = rawkey();
    if (k != '[') { _ppush = k; return 0; }    /* lone ESC: dropped */
    k = rawkey();
    if (k != '8') { _pseq = 1; _pseqb = k; return 0; }
    st = 0; b = 0; c = 0;
    while (k != 't' && keyrdy()) {
        k = rawkey();
        if (k == 27) { _ppush = 27; return 0; }  /* a following event */
        if (k >= '0' && k <= '9') {
            if (st == 1) { b = b * 10 + k - '0'; }
            if (st == 2) { c = c * 10 + k - '0'; }
        }
        if (k == ';') { st = st + 1; }
    }
    if (k == 't' && b > 0 && c > 0) { _prows = b; _pcols = c; }
    return 0;
}

int ptr_init() {
    _ppush = 0; _pseq = 0;
    _ptsize(); _pmapin();
    outc(27); outs("[?1002h"); outc(27); outs("[?1006h");
    return 0;
}
int ptr_done() {
    outc(27); outs("[?1006l"); outc(27); outs("[?1002l");
    return 0;
}

/* one SGR report, after ESC [ < is consumed: b;x;y then M/m.
 * Returns the event type, or 0 with ptr_key=0 for ignored buttons. */
int _pmouse() {
    int b; int x; int y; int st; int k; int fin;
    b = 0; x = 0; y = 0; st = 0; fin = 0;
    while (fin == 0) {
        k = rawkey();
        if (k >= '0' && k <= '9') {
            if (st == 0) { b = b * 10 + k - '0'; }
            if (st == 1) { x = x * 10 + k - '0'; }
            if (st == 2) { y = y * 10 + k - '0'; }
        } else if (k == ';') { st = st + 1; }
        else { fin = k; }
    }
    ptr_key = 0;
    if (b >= 64) { return 0; }                 /* wheel: ignored */
    ptr_x = _pmapx(x); ptr_y = _pmapwy(y);
    if (fin == 'm') { return 3; }
    if ((b & 3) == 2) { return 4; }            /* right press */
    if (b & 32) { return 2; }                  /* drag */
    return 1;                                  /* press */
}

int ptr_ev() {
    int k;
    while (1) {
        if (_pseq) { _pseq = 0; k = _pseqb; }
        else {
            k = rawkey();
            if (k != 27) { ptr_key = k; return 0; }
            k = rawkey();
            if (k != '[') { ptr_key = 27; _ppush = k; return 0; }
            k = rawkey();
        }
        if (k == '<') {
            k = _pmouse();
            if (k != 0 || ptr_key != 0) { return k; }
        }
        else if (k == 'A') { ptr_key = 128; return 0; }
        else if (k == 'B') { ptr_key = 129; return 0; }
        else if (k == 'C') { ptr_key = 130; return 0; }
        else if (k == 'D') { ptr_key = 131; return 0; }
        else {
            /* any other CSI (a late size reply, an unasked report):
               swallow parameters up to its final byte */
            while ((k >= '0' && k <= '9') || k == ';') { k = rawkey(); }
        }
    }
    return 0;
}
