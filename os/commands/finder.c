/* finder.c -- the full-screen Finder desktop (two-mode P4).
 *
 * The Mac-style desktop for the graphics mode: ONE program owns the whole screen
 * (no tiling, no z-order, no per-window records -- the natural fit for the
 * single-TPA machine). A menu bar across the top; the current directory filling
 * the rest as a scrolling file list. Keyboard-driven:
 *
 *   Up / Down (or k / j)   move the selection
 *   ENTER                  open -- a directory navigates INTO it; a .BIN LAUNCHES
 *                          full-screen (SYS_EXEC: this program BECOMES the app)
 *   Backspace / Left       go UP a directory
 *   q  or  ESC             quit the desktop -> back to the command-line OS
 *
 * Launching an app is a full-screen program swap (SYS_EXEC). Auto-return to the
 * desktop on the app's quit (the -d/-w resume chain), an Apps menu, mouse, and
 * the file ops (rename/duplicate/move) are follow-ups -- see BACKLOG.md. Grows
 * out of desk.c's FILES logic, made full-screen (docs/p8x-two-mode-design.md).
 */

//#use abi        /* SYS_GETCWD / SYS_EXEC, FOPENDIR/FNEXT, CONIN */
//#use dirent     /* de_read / de_isdir / de_isfile / de_isdot, de[] */
//#use ptr        /* rawkey() -- arrow-decoded console keys */

//#define GLDATA  0xFF50
//#define GLSTAT  0xFF51
//#define GFXPRES 0x60A4  /* 1 = GL card fitted */
//#define GTSUSP  0x60A7  /* 1 = this app owns the screen (suspend the glass console) */

#define NN 24            /* max entries cached / rows shown */

char cpath[64];          /* the directory being browsed */
char fnam[312];          /* NN(24) names x 13 bytes each (p8cc needs a literal size) */
char fdir[24];           /* per entry: 1 = a directory */
int  fcnt;               /* how many entries */
int  fsel;               /* selected row (0..fcnt-1) */
int  ftop;               /* first visible row (scroll) */
char vpath[68];          /* scratch: a full path to launch */

/* ---- GL emission (full-screen, no window offset) --------------------------- */
int gp(int v) { while (peek(GLSTAT) & 128) { } poke(GLDATA, v); return 0; }
int gw(int v) { gp(v & 255); gp((v / 256) & 255); return 0; }
int pen(int c) { gp(6); gp((c >> 11) & 31); gp((c >> 5) & 63); gp(c & 31); return 0; }
int gtext(int x, int y, char *s) {           /* MOVE3 x,y,0 then TEXT */
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
/* establish the port + text projection: full-screen window/viewport, PROJCT 0
 * (text strokes live at z=0, which the native camera near-clips), identity model
 * matrix, unit text size. Configure from scratch -- don't trust inherited state. */
int gsetup() {
    gp(179); gw(0); gw(479); gw(0); gw(271);   /* WINDOW  0..479 0..271 */
    gp(178); gw(0); gw(479); gw(0); gw(271);   /* VWPORT  identity      */
    gp(176); gw(0);                            /* PROJCT 0              */
    gp(144);                                   /* MDIDEN               */
    gp(129); gw(256);                          /* TSIZE 1.0 (256 = x1) */
    return 0;
}

/* read a key, decoding arrow escape sequences (ESC [ A/B/C/D) that arrive as raw
 * bytes on the serial console (rawkey is raw -- the WM kernel used to decode these,
 * but the full-screen desktop has no kernel). Returns 128 up / 129 down / 130 left
 * / 131 right; a lone ESC returns 27 (quit); otherwise the byte. A bounded spin
 * after ESC lets the [X bytes catch up over a slow serial link. */
int getkey() {
    int k; int i;
    k = rawkey();
    if (k != 27) { return k; }
    i = 0; while (i < 20000 && keyrdy() == 0) { i = i + 1; }
    if (keyrdy() == 0) { return 27; }              /* lone ESC */
    k = rawkey();
    if (k != '[') { return 27; }                   /* not an arrow: treat as ESC */
    i = 0; while (i < 20000 && keyrdy() == 0) { i = i + 1; }
    k = rawkey();
    if (k == 'A') { return 128; }                  /* up    */
    if (k == 'B') { return 129; }                  /* down  */
    if (k == 'D') { return 130; }                  /* left  */
    if (k == 'C') { return 131; }                  /* right */
    return 0;                                       /* unknown sequence: ignore */
}

/* ---- path helpers (from desk.c) -------------------------------------------- */
int scopy(char *d, char *c, int cap) {
    int i; i = 0;
    while (c[i] != 0 && i < cap) { d[i] = c[i]; i = i + 1; }
    d[i] = 0; return 0;
}
int pjoin(char *out, char *dir, char *leaf) {      /* out = dir + "/" + leaf */
    int i; int j;
    i = 0; while (dir[i] != 0) { out[i] = dir[i]; i = i + 1; }
    if (i > 1) { out[i] = '/'; i = i + 1; }
    j = 0; while (leaf[j] != 0) { out[i] = leaf[j]; i = i + 1; j = j + 1; }
    out[i] = 0; return 0;
}
int pup() {                                        /* strip one component off cpath */
    int r; r = 0;
    while (cpath[r] != 0) { r = r + 1; }
    while (r > 1 && cpath[r] != '/') { r = r - 1; }
    if (r == 0) { r = 1; }
    cpath[r] = 0;
    if (cpath[1] == 0) { cpath[0] = '/'; cpath[1] = 0; }
    return 0;
}
int isbin(char *s) {                               /* 1 if name ends .BIN (case-blind) */
    int n; n = 0;
    while (s[n] != 0) { n = n + 1; }
    if (n < 4) { return 0; }
    if (s[n-4] != '.') { return 0; }
    return (s[n-3] & 95) == 'B' && (s[n-2] & 95) == 'I' && (s[n-1] & 95) == 'N';
}

/* ---- read cpath's entries into fnam[]/fdir[] (from desk.c's fscan) ---------- */
int fscan() {
    int r; int j; int k;
    fcnt = 0; fsel = 0; ftop = 0;
    r = bios(FOPENDIR, cpath, 0);
    if (r & 256) { return 1; }
    r = bios(FNEXT, 0, 0);
    while ((r & 256) == 0 && fcnt < NN) {
        de_read();
        j = de[0] & 255;
        /* keep real files/dirs with a printable name; skip '.', deleted slots
         * ($E5) and the volume label -- but keep '..' */
        if ((de_isfile() || de_isdir()) && j >= 33 && j <= 126 &&
            (de_isdot() == 0 || (de[1] & 255) == '.')) {
            j = 0; k = fcnt * 13;
            while (j < 12) { if ((de[j] & 255) > 32) { fnam[k] = de[j]; k = k + 1; } j = j + 1; }
            fnam[k] = 0;
            if (k > fcnt * 13) { fdir[fcnt] = de_isdir(); fcnt = fcnt + 1; }
        }
        r = bios(FNEXT, 0, 0);
    }
    return 0;
}

/* ---- draw the whole desktop ------------------------------------------------ */
int draw() {
    int r; int y;
    pen(0); gp(7); gp(0); gp(0); gp(0);            /* FLOOD black: the desktop */
    /* menu bar: a white strip across the top with black labels */
    pen(65535); fillrect(0, 258, 479, 271);
    pen(0);
    gtext(4, 261, "FINDER");
    gtext(72, 261, cpath);
    pen(0);
    gtext(300, 261, "ENTER OPEN  BKSP UP  Q QUIT");
    /* file list, top-down from just below the bar */
    r = ftop; y = 244;
    while (r < fcnt && y > 6) {
        if (r == fsel) { pen(65504); fillrect(0, y - 2, 479, y + 8); pen(0); }  /* selection: yellow bar */
        else if (fdir[r]) { pen(2047); }          /* directory: cyan */
        else { pen(65535); }                      /* file: white */
        gtext(8, y, fnam + r * 13);
        if (fdir[r]) { gtext(2, y, "/"); }
        r = r + 1; y = y - 10;
    }
    return 0;
}

/* keep the selection on screen (adjust the scroll window) */
int reveal() {
    if (fsel < ftop) { ftop = fsel; }
    if (fsel >= ftop + NN) { ftop = fsel - (NN - 1); }
    return 0;
}

/* open the selected entry: a directory navigates in; a .BIN launches. */
int open_sel() {
    char *nm;
    if (fcnt == 0) { return 0; }
    nm = fnam + fsel * 13;
    if (fdir[fsel]) {                              /* directory */
        if (nm[0] == '.' && nm[1] == '.') { pup(); }
        else { pjoin(vpath, cpath, nm); scopy(cpath, vpath, 60); }
        fscan();
        return 0;
    }
    if (isbin(nm)) {                               /* a program: launch full-screen */
        pjoin(vpath, cpath, nm);
        poke(GTSUSP, 0);                           /* release the screen for the app */
        bios(SYS_EXEC, vpath, 0);                  /* BECOME it (no return on success) */
        poke(GTSUSP, 1);                           /* only here if exec failed */
    }
    return 0;                                      /* other files: ignored for now */
}

int main() {
    int k; int going;
    if (peek(GFXPRES) == 0) { puts("?No display"); return 1; }
    poke(GTSUSP, 1);                               /* claim the screen */
    gsetup();                                      /* port + text projection */
    bios(SYS_GETCWD, cpath, 0);                    /* start where we were launched */
    if (cpath[0] == 0) { cpath[0] = '/'; cpath[1] = 0; }
    fscan();
    draw();
    going = 1;
    while (going) {
        k = getkey();
        if (k == 'q' || k == 'Q' || k == 27) { going = 0; }
        else if (k == 129 || k == 'j') { if (fsel < fcnt - 1) { fsel = fsel + 1; } }   /* down */
        else if (k == 128 || k == 'k') { if (fsel > 0) { fsel = fsel - 1; } }          /* up */
        else if (k == 13 || k == 10) { open_sel(); }                                   /* open */
        else if (k == 8 || k == 127 || k == 130) { pup(); fscan(); }                   /* up dir */
        if (going) { reveal(); draw(); }
    }
    poke(GTSUSP, 0);                               /* release the console */
    return 0;
}
