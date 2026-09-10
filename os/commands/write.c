/* write.c -- the Write app: a full-screen text editor for the GL display
 * (two-mode P5). Open a text file (or a new one), edit it on screen, save it.
 *
 *   write /NOTES.TXT     edit that file (created if absent)
 *   write                a scratch buffer (save writes /WRITE.TXT)
 *
 * Keys:  printable        insert at the cursor
 *        ENTER            insert a newline
 *        Backspace        delete the char before the cursor
 *        Left/Right       move within the text
 *        Up/Down          move to the same column on the line above/below
 *        ^O               save
 *        ^X or ESC        quit -> back to the Finder desktop
 *
 * The cursor is a yellow block; a white menu bar shows the file + key hints.
 * A single flat buffer (2 KB); the whole thing redraws each keystroke -- simple
 * over fast, the machine has cycles to spare. Launched from Finder's APPS menu.
 */

//#use abi     /* FOPEN/FGETB/FWOPEN/FPUTB/FCLOSE/FRESOLVE/FDELETE, RDBUF, SYS_EXEC, argstr */
//#use ptr     /* rawkey */

//#define GLDATA  0xFF50
//#define GLSTAT  0xFF51
//#define GFXPRES 0x60A4
//#define GTSUSP  0x60A7

char buf[2000];          /* the text */
int  blen;               /* length */
int  cur;                /* cursor offset (0..blen) */
char fpath[64];          /* the file being edited */
int  dirty;              /* unsaved edits (shown in the bar) */

/* ---- GL emission (full-screen) --------------------------------------------- */
int gp(int v) { while (peek(GLSTAT) & 128) { } poke(GLDATA, v); return 0; }
int gw(int v) { gp(v & 255); gp((v / 256) & 255); return 0; }
int pen(int c) { gp(6); gp((c >> 11) & 31); gp((c >> 5) & 63); gp(c & 31); return 0; }
int gtext(int x, int y, char *s) {
    int i;
    gp(18); gw(x); gw(y); gw(0);
    i = 0; while (s[i]) { i = i + 1; }
    gp(128); gp(i);
    i = 0; while (s[i]) { gp(s[i]); i = i + 1; }
    return 0;
}
int fillrect(int x0, int y0, int x1, int y1) {
    gp(224); gp(1); gp(16); gw(x0); gw(y0); gp(52); gw(x1); gw(y1); gp(224); gp(0);
    return 0;
}
int gsetup() {
    gp(179); gw(0); gw(479); gw(0); gw(271);
    gp(178); gw(0); gw(479); gw(0); gw(271);
    gp(176); gw(0);                            /* PROJCT 0 */
    gp(144);                                   /* MDIDEN   */
    gp(129); gw(256);                          /* TSIZE 1.0 */
    return 0;
}
int getkey() {                                 /* decode arrow escapes (see finder) */
    int k; int i;
    k = rawkey();
    if (k != 27) { return k; }
    i = 0; while (i < 20000 && keyrdy() == 0) { i = i + 1; }
    if (keyrdy() == 0) { return 27; }
    k = rawkey();
    if (k != '[') { return 27; }
    i = 0; while (i < 20000 && keyrdy() == 0) { i = i + 1; }
    k = rawkey();
    if (k == 'A') { return 128; }
    if (k == 'B') { return 129; }
    if (k == 'D') { return 130; }
    if (k == 'C') { return 131; }
    return 0;
}

/* ---- buffer ops ------------------------------------------------------------ */
int load() {
    int r; int done;
    blen = 0; cur = 0; dirty = 0;
    bios(FRESOLVE, fpath, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { return 0; }   /* new file: empty buffer */
    done = 0;
    while (done == 0) {
        r = bios(FGETB, 0, 0);
        if (r & 256) { done = 1; }
        else if (blen < 1999) { buf[blen] = r & 255; blen = blen + 1; }
        else { done = 1; }
    }
    return 0;
}
int save() {
    int i;
    bios(FRESOLVE, fpath, 0);
    bios(FDELETE, fpath, 0);
    bios(FRESOLVE, fpath, 0);
    bios(FWOPEN, 0, 0);
    i = 0; while (i < blen) { bios(FPUTB, 0, buf[i]); i = i + 1; }
    bios(FCLOSE, 0, 0);
    dirty = 0;
    return 0;
}
int ins(int c) {
    int i;
    if (blen >= 1999) { return 0; }
    i = blen; while (i > cur) { buf[i] = buf[i - 1]; i = i - 1; }
    buf[cur] = c; blen = blen + 1; cur = cur + 1; dirty = 1;
    return 0;
}
int backsp() {
    int i;
    if (cur == 0) { return 0; }
    i = cur; while (i < blen) { buf[i - 1] = buf[i]; i = i + 1; }
    blen = blen - 1; cur = cur - 1; dirty = 1;
    return 0;
}
/* start of the line containing offset p */
int lstart(int p) {
    while (p > 0 && buf[p - 1] != 10) { p = p - 1; }
    return p;
}
/* offset of the next line's start after p (or blen) */
int lnext(int p) {
    while (p < blen && buf[p] != 10) { p = p + 1; }
    if (p < blen) { p = p + 1; }
    return p;
}
int col_of(int p) { return p - lstart(p); }

int cur_up() {
    int col; int ls; int pls; int plen;
    col = col_of(cur);
    ls = lstart(cur);
    if (ls == 0) { return 0; }                 /* already top line */
    pls = lstart(ls - 1);                       /* previous line start */
    plen = (ls - 1) - pls;                      /* its length (excl newline) */
    if (col > plen) { col = plen; }
    cur = pls + col;
    return 0;
}
int cur_down() {
    int col; int nl; int nlen; int p;
    col = col_of(cur);
    nl = lnext(cur);
    if (nl >= blen && (blen == 0 || buf[blen - 1] != 10)) {
        /* no next line unless the current line ends in \n */
        if (nl > blen) { return 0; }
    }
    if (nl > blen) { return 0; }
    p = nl; nlen = 0;
    while (p < blen && buf[p] != 10) { p = p + 1; nlen = nlen + 1; }
    if (col > nlen) { col = nlen; }
    cur = nl + col;
    if (cur > blen) { cur = blen; }
    return 0;
}

/* ---- render ---------------------------------------------------------------- */
int draw() {
    int i; int x; int y; int col; int c; int done;
    pen(0); gp(7); gp(0); gp(0); gp(0);            /* clear */
    pen(65535); fillrect(0, 258, 479, 271);        /* menu bar */
    pen(0);
    gtext(4, 261, "WRITE");
    gtext(56, 261, fpath);
    if (dirty) { gtext(300, 261, "*"); }
    gtext(312, 261, "^O SAVE  ^X QUIT");
    /* text from the top, wrapping at 78 cols, clipping at the bottom */
    x = 2; y = 246; col = 0; i = 0; done = 0;
    while (done == 0) {
        if (i == cur) { pen(65504); fillrect(x, y - 1, x + 5, y + 7); }   /* cursor block */
        if (i >= blen) { done = 1; }
        else {
            c = buf[i] & 255;
            if (c == 10) { x = 2; y = y - 10; col = 0; }
            else if (c >= 32 && c < 127) {
                char s[2]; s[0] = c; s[1] = 0;
                if (i == cur) { pen(0); } else { pen(65535); }
                gtext(x, y, s);
                x = x + 6; col = col + 1;
                if (col >= 78) { x = 2; y = y - 10; col = 0; }
            }
            i = i + 1;
        }
        if (y <= 4) { done = 1; }
    }
    return 0;
}

int main() {
    int k; int going; int i; char *a;
    if (peek(GFXPRES) == 0) { puts("?No display"); return 1; }
    poke(GTSUSP, 1);                               /* claim the screen */
    gsetup();
    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == '/' || (*a >= 'A' && *a != 0 && *a != 13)) {
        i = 0;
        while (a[i] != 0 && a[i] != 13 && a[i] != 10 && a[i] != 32 && i < 60) { fpath[i] = a[i]; i = i + 1; }
        fpath[i] = 0;
    } else {
        fpath[0] = '/'; fpath[1] = 'W'; fpath[2] = 'R'; fpath[3] = 'I';
        fpath[4] = 'T'; fpath[5] = 'E'; fpath[6] = '.'; fpath[7] = 'T';
        fpath[8] = 'X'; fpath[9] = 'T'; fpath[10] = 0;
    }
    load();
    draw();
    going = 1;
    while (going) {
        k = getkey();
        if (k == 24 || k == 27) { going = 0; }                       /* ^X / ESC: quit */
        else if (k == 15) { save(); }                                /* ^O: save */
        else if (k == 131) { if (cur < blen) { cur = cur + 1; } }    /* right */
        else if (k == 130) { if (cur > 0) { cur = cur - 1; } }       /* left */
        else if (k == 128) { cur_up(); }                             /* up */
        else if (k == 129) { cur_down(); }                           /* down */
        else if (k == 8 || k == 127) { backsp(); }                   /* backspace */
        else if (k == 13 || k == 10) { ins(10); }                    /* newline */
        else if (k >= 32 && k < 127) { ins(k); }                     /* printable */
        if (going) { draw(); }
    }
    poke(GTSUSP, 0);
    bios(SYS_EXEC, "/bin/finder.bin", 0);          /* back to the desktop */
    return 0;
}
