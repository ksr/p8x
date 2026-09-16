/* finder.c -- the full-screen Finder desktop (two-mode P4).
 *
 * The Mac-style desktop for the graphics mode: ONE program owns the whole screen
 * (no tiling, no z-order, no per-window records -- the natural fit for the
 * single-TPA machine). A menu bar across the top; the current directory filling
 * the rest as a scrolling file list. Keyboard-driven:
 *
 *   Up / Down (or k / j)   move the selection
 *   ENTER                  open -- a directory navigates INTO it; a .BIN LAUNCHES
 *                          full-screen and AUTO-RETURNS here when it quits
 *   Backspace / Left       go UP a directory
 *   a                      the APPS menu (paint / term / write / ...)
 *   f                      the FILE menu (rename / duplicate / move / new / delete)
 *   q  or  ESC             quit the desktop -> back to the command-line OS
 *
 * Launching an app is a full-screen swap that comes back: Finder writes a two-line
 * script -- "run <app>" then "run /bin/finder.bin <dir>" -- and hands it to the
 * shell (SYS_RUNSH). The app quitting is a plain return to the shell, which flows
 * straight on to the second line, re-launching Finder in the same directory. No
 * per-app flag is needed (the mechanism the WM TERM used). The file operations
 * reuse that exact chain: an op builds a shell command (mv/cp/del/rmdir/mkdir) and
 * run_op runs it then re-launches Finder -- so P8XFS needs no rename/rmdir
 * primitive of its own. Still follow-ups (BACKLOG.md): mouse, and real pull-down
 * menus in place of the key-hint bar. Grows out of desk.c's FILES logic, made
 * full-screen (docs/p8x-two-mode-design.md).
 */

//#use abi        /* SYS_GETCWD / SYS_EXEC, FOPENDIR/FNEXT, CONIN */
//#use mem     /* GFXPRES/GTSUSP/GCONEN -- the graphics/console flags, from the memory map */
//#use dirent     /* de_read / de_isdir / de_isfile / de_isdot, de[] */
//#use ptr        /* rawkey() -- arrow-decoded console keys */

//#define GLDATA  0xFF50
//#define GLSTAT  0xFF51

#define NN 24            /* max entries cached / rows shown */

char cpath[64];          /* the directory being browsed */
char fnam[312];          /* NN(24) names x 13 bytes each (p8cc needs a literal size) */
char fdir[24];           /* per entry: 1 = a directory */
int  fcnt;               /* how many entries */
int  fsel;               /* selected row (0..fcnt-1) */
int  ftop;               /* first visible row (scroll) */
char vpath[68];          /* scratch: a full path to launch (also the op SOURCE path) */
char dpath[68];          /* scratch: a file op's DESTINATION path */
char icmd[96];           /* scratch: a "run" command with an argument (image) */
char cmdbuf[168];        /* scratch: a built shell command line for a file op */
char nbuf[16];           /* scratch: a name/path typed into the input dialog */

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

/* ---- following mouse cursor (1003 free-motion) --------------------------- *
 * An XOR crosshair on the bitmap: drawing it twice erases it (no read-back).
 * LINFUN 4 = XOR and applies to OUTLINES only, so the arms are degenerate
 * rectlines (a box with zero height/width = a line). Left at LINFUN 0 after;
 * the pen is left white, which is fine -- every draw() sets its own pens. */
int _curx; int _cury; int _curon;
int cur_xdraw() {
    gp(235); gp(4);                                  /* LINFUN XOR */
    penrgb(31, 63, 31);                              /* white inverts under XOR, visible anywhere */
    rectline(_curx - 4, _cury, _curx + 4, _cury);    /* horizontal arm */
    rectline(_curx, _cury - 4, _curx, _cury + 4);    /* vertical arm   */
    gp(235); gp(0);                                  /* LINFUN replace */
    return 0;
}
int cur_show() { if (_curon == 0) { cur_xdraw(); _curon = 1; } return 0; }
int cur_hide() { if (_curon) { cur_xdraw(); _curon = 0; } return 0; }
int cur_to(int x, int y) { cur_hide(); _curx = x; _cury = y; cur_show(); return 0; }

/* block for the next KEY, letting lib_ptr consume (and discard) any mouse SGR
 * reports that arrive meanwhile -- used by the menus and text dialogs, which are
 * keyboard-only. ptr_ev() returns 0 for a key (in ptr_key: arrows are 128..131),
 * 1..4 for pointer events. The main loop calls ptr_ev() directly so it can act on
 * the mouse; the dialogs just want keys. */
int getkey() {
    while (1) { if (ptr_ev() == 0) { return ptr_key; } }
    return 0;
}

/* ---- icons (vector, drawn from GL rects; no image assets) ------------------ *
 * Each icon is ~40x34, drawn from an origin (ix,iy) = its bottom-left in window
 * coords (y up). Four kinds: a manila folder, a white document, a cyan "program"
 * page, and a document with a colour chip for a picture. */
int penrgb(int r, int g, int b) { gp(6); gp(r); gp(g); gp(b); return 0; }
int rectline(int x0, int y0, int x1, int y1) {   /* outline rect (leaves PRMFIL 0) */
    gp(224); gp(0); gp(16); gw(x0); gw(y0); gp(52); gw(x1); gw(y1);
    return 0;
}
int icon_folder(int ix, int iy) {
    penrgb(24, 34, 6);  fillrect(ix + 2, iy + 24, ix + 18, iy + 31);   /* tab   */
    penrgb(30, 48, 12); fillrect(ix, iy, ix + 40, iy + 26);            /* body  */
    penrgb(8, 14, 2);   rectline(ix, iy, ix + 40, iy + 26);
    return 0;
}
int icon_doc(int ix, int iy, int tint) {          /* tint 0=white 1=cyan program */
    if (tint) { penrgb(8, 44, 34); } else { penrgb(31, 63, 31); }
    fillrect(ix + 6, iy, ix + 34, iy + 34);                            /* page  */
    penrgb(12, 24, 12);
    fillrect(ix + 11, iy + 27, ix + 29, iy + 28);                      /* lines */
    fillrect(ix + 11, iy + 22, ix + 29, iy + 23);
    fillrect(ix + 11, iy + 17, ix + 25, iy + 18);
    penrgb(6, 12, 6); rectline(ix + 6, iy, ix + 34, iy + 34);
    return 0;
}
int icon_pic(int ix, int iy) {
    penrgb(31, 63, 31); fillrect(ix + 6, iy, ix + 34, iy + 34);        /* page  */
    penrgb(6, 40, 28);  fillrect(ix + 11, iy + 6, ix + 29, iy + 24);   /* image */
    penrgb(31, 50, 0);  fillrect(ix + 14, iy + 9, ix + 20, iy + 15);   /* a mark*/
    penrgb(6, 12, 6);   rectline(ix + 6, iy, ix + 34, iy + 34);
    return 0;
}
/* which icon an entry gets: 1 folder, 2 program (.BIN), 3 picture (.P8I), 0 doc */
int etype(int i) {
    char *nm;
    if (fdir[i]) { return 1; }
    nm = fnam + i * 13;
    if (isbin(nm)) { return 2; }
    if (isp8i(nm)) { return 3; }
    return 0;
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
int isp8i(char *s) {                               /* 1 if name ends .P8I (case-blind) */
    int n; n = 0;
    while (s[n] != 0) { n = n + 1; }
    if (n < 4) { return 0; }
    if (s[n-4] != '.') { return 0; }
    return (s[n-3] & 95) == 'P' && s[n-2] == '8' && (s[n-1] & 95) == 'I';
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

/* ---- the icon grid --------------------------------------------------------- *
 * Entries are drawn as icons in a 5-column grid (20 per page), each with its name
 * beneath. The selected cell gets a highlight box. PGCOLS/PGROWS below and the
 * hit test in cell_at() must agree. */
#define PGCOLS 5
#define PGROWS 4
#define PGN    20            /* PGCOLS*PGROWS -- p8cc wants a literal */
#define COLW   96            /* 480 / PGCOLS */
#define ROWH   60

/* the cell top edge (window y, y up) for page-row r (0 = top) */
int cell_top(int r) { return 246 - ROWH * r; }

int draw() {
    int s; int idx; int row; int col; int ix; int ct; int t; char *nm;
    gp(7); gp(2); gp(8); gp(12);                   /* FLOOD: a blue-grey desktop */
    _curon = 0;                                    /* the flood wiped the XOR cursor */
    /* menu bar: a white strip across the top with black labels */
    pen(65535); fillrect(0, 258, 479, 271);
    pen(0);
    gtext(4, 261, "FINDER");
    gtext(72, 261, cpath);
    gtext(206, 261, "F FILE  A APPS  R-CLICK MENU  Q QUIT");
    /* the icons */
    s = 0;
    while (s < PGN && ftop + s < fcnt) {
        idx = ftop + s;
        row = s / PGCOLS; col = s - row * PGCOLS;
        ix = col * COLW + 28;
        ct = cell_top(row);
        if (idx == fsel) {                         /* selection highlight box */
            penrgb(6, 18, 28); fillrect(col * COLW + 2, ct - 58, col * COLW + 94, ct - 2);
        }
        t = etype(idx);
        if (t == 1) { icon_folder(ix, ct - 42); }
        else if (t == 2) { icon_doc(ix, ct - 42, 1); }
        else if (t == 3) { icon_pic(ix, ct - 42); }
        else { icon_doc(ix, ct - 42, 0); }
        nm = fnam + idx * 13;                       /* name (<=12 chars) fits the column */
        pen(65535); gtext(col * COLW + 6, ct - 54, nm);
        s = s + 1;
    }
    cur_show();                                     /* the mouse cursor sits on top */
    return 0;
}

/* which entry index is at window point (px,py). Sets the global cell_ok to 1 and
 * returns the index on a hit, else cell_ok=0. A flag (not a sentinel return)
 * because p8cc compares ints UNSIGNED -- a -1 "none" would test >= 0 as true, and
 * an out-of-range sentinel is fragile; a 0/1 flag sidesteps all of that. Inverse
 * of the grid layout in draw(). */
int cell_ok;
int cell_at(int px, int py) {
    int col; int row; int s; int r;
    cell_ok = 0; r = 0;                              /* SINGLE return path (early
                                                       returns tripped a codegen bug) */
    if (py <= 256) {                                 /* below the menu bar */
        row = (246 - py) / ROWH;                     /* py 247..256 -> huge (unsigned) */
        if (row < PGROWS) {
            col = px / COLW; if (col >= PGCOLS) { col = PGCOLS - 1; }
            s = row * PGCOLS + col;
            if (ftop + s < fcnt) { cell_ok = 1; r = ftop + s; }
        }
    }
    return r;
}

/* put the selection on the visible page (page-aligned scrolling) */
int reveal() { ftop = (fsel / PGN) * PGN; return 0; }

/* emit one string to the open write stream */
int putstr(char *s) { int i; i = 0; while (s[i]) { bios(FPUTB, 0, s[i]); i = i + 1; } return 0; }

/* write /FINDER.SCR = "run <app>\nrun /bin/finder.bin <cpath>\n": run the app,
 * then RE-LAUNCH the desktop in the same directory. Handed to the shell with
 * SYS_RUNSH, so the app quitting (a plain return to the shell) flows straight on
 * to the second line -- auto-return to Finder, no per-app flag needed. */
int write_launch(char *app) {
    bios(FRESOLVE, "/FINDER.SCR", 0);
    bios(FDELETE, "/FINDER.SCR", 0);               /* replace any old one */
    bios(FRESOLVE, "/FINDER.SCR", 0);
    bios(FWOPEN, 0, 0);
    putstr("run "); putstr(app); bios(FPUTB, 0, 10);
    putstr("run /bin/finder.bin "); putstr(cpath); bios(FPUTB, 0, 10);
    bios(FCLOSE, 0, 0);
    return 0;
}

/* launch an app full-screen with auto-return: write the script + run it (no
 * return -- the shell re-launches us via the script's second line). */
int launch(char *app) {
    write_launch(app);
    bios(SYS_RUNSH, "/FINDER.SCR", 0);
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
    pjoin(vpath, cpath, nm);                       /* the file's absolute path */
    if (isbin(nm)) {                               /* a program: launch full-screen */
        launch(vpath);                             /* no return on success */
    }
    if (isp8i(nm)) {                               /* a picture: open it in image */
        char *pfx; int i; int j;
        pfx = "/bin/image.bin ";
        i = 0; while (pfx[i]) { icmd[i] = pfx[i]; i = i + 1; }
        j = 0; while (vpath[j]) { icmd[i] = vpath[j]; i = i + 1; j = j + 1; }
        icmd[i] = 0;
        launch(icmd);                              /* "run /bin/image.bin <path>"; no return */
    }
    return 0;                                      /* other files: ignored */
}

/* the APPS menu: a dropdown of the desktop's apps, launched by their letter.
 * Drawn as an overlay; one keystroke picks an app (and launches it -- no return)
 * or closes the menu. Reuses the launch/auto-return chain. */
int apps_menu() {
    int k;
    pen(65535); fillrect(58, 138, 250, 256);       /* white panel */
    pen(0);     fillrect(60, 240, 248, 254);       /* dark title band */
    pen(65535); gtext(66, 244, "APPS");
    pen(0);
    gtext(66, 226, "P  PAINT");
    gtext(66, 214, "T  TERM");
    gtext(66, 202, "W  WRITE");
    gtext(66, 190, "C  CUBE");
    gtext(66, 178, "H  HOUSE");
    gtext(66, 166, "G  GL");
    gtext(66, 150, "ESC CANCEL");
    k = getkey();
    if (k == 'p' || k == 'P') { launch("/bin/paint.bin"); }
    if (k == 't' || k == 'T') { launch("/bin/term.bin"); }
    if (k == 'w' || k == 'W') { launch("/bin/write.bin"); }
    if (k == 'c' || k == 'C') { launch("/bin/cube.bin"); }
    if (k == 'h' || k == 'H') { launch("/bin/house.bin"); }
    if (k == 'g' || k == 'G') { launch("/bin/gl.bin"); }
    return 0;                                       /* ESC/other: caller redraws, menu gone */
}

/* ---- file operations ------------------------------------------------------ *
 * P8XFS has no rename/rmdir primitive of its own, so rather than reimplement the
 * filesystem here the Finder DELEGATES to the shell commands that already do the
 * job (mv/cp/del/rmdir/mkdir): each op builds a command line and hands it to the
 * same script-and-return chain that launches apps -- run_op writes
 *   <command>\nrun /bin/finder.bin <cpath>\n
 * and SYS_RUNSHs it, so the command runs and the Finder re-launches in the same
 * directory (re-scanning, so the result is on screen). That gets cross-directory
 * moves and empty-directory removal for free from tested commands. */

/* append s to cmdbuf at pos; return the new position (cmdbuf stays NUL-terminated) */
int apnd(int pos, char *s) {
    int i; i = 0;
    while (s[i]) { cmdbuf[pos] = s[i]; pos = pos + 1; i = i + 1; }
    cmdbuf[pos] = 0;
    return pos;
}

/* a modal text-entry dialog: draw a box with the label and the text typed so far,
 * read a name into dst (<=14 chars). ENTER accepts (returns 1 if non-empty), ESC
 * cancels (returns 0, dst emptied). Redraws every keystroke; the caller repaints
 * the desktop afterwards. */
int prompt_input(char *label, char *dst) {
    int k; int n; int going;
    n = 0; dst[0] = 0; going = 1;
    while (going) {
        pen(65535); fillrect(48, 116, 432, 156);       /* white dialog */
        pen(0);     fillrect(50, 148, 430, 154);       /* title band */
        pen(65535); gtext(56, 149, label);
        pen(0);     gtext(56, 130, dst);
        gtext(56, 119, "ENTER OK   ESC CANCEL");
        k = getkey();
        if (k == 13 || k == 10) { going = 0; }
        else if (k == 27) { dst[0] = 0; return 0; }
        else if (k == 8 || k == 127) { if (n > 0) { n = n - 1; dst[n] = 0; } }
        else if (k >= 32 && k < 127 && n < 14) { dst[n] = k; n = n + 1; dst[n] = 0; }
    }
    return n > 0;
}

/* a modal Y/N confirmation (for the destructive delete). 1 = the user pressed Y. */
int confirm(char *label) {
    int k;
    pen(65535); fillrect(48, 120, 432, 156);
    pen(0); gtext(56, 140, label);
    gtext(56, 126, "Y = YES   any other key = NO");
    k = getkey();
    return k == 'y' || k == 'Y';
}

/* write /FINDER.SCR = cmdbuf then the Finder re-launch, and run it (no return). */
int run_op() {
    bios(FRESOLVE, "/FINDER.SCR", 0);
    bios(FDELETE, "/FINDER.SCR", 0);
    bios(FRESOLVE, "/FINDER.SCR", 0);
    bios(FWOPEN, 0, 0);
    putstr(cmdbuf); bios(FPUTB, 0, 10);
    putstr("run /bin/finder.bin "); putstr(cpath); bios(FPUTB, 0, 10);
    bios(FCLOSE, 0, 0);
    bios(SYS_RUNSH, "/FINDER.SCR", 0);                  /* no return */
    return 0;
}

/* 1 if the selection is a real, operable entry (exists and is not "..") */
int op_target(char **nmp) {
    char *nm;
    if (fcnt == 0) { return 0; }
    nm = fnam + fsel * 13;
    if (nm[0] == '.' && nm[1] == '.') { return 0; }
    *nmp = nm;
    return 1;
}

/* do one file operation, all five folded into a single builder to keep the
 * binary small. kind: 1 rename, 2 duplicate (files only), 3 move (to a typed
 * dir), 4 new folder (no target), 5 delete. On confirm it does NOT return -- it
 * re-launches via run_op; a cancel returns so the caller repaints. */
int do_op(int kind) {
    char *nm; int p;
    if (kind == 4) {                                    /* new folder: no target */
        if (prompt_input("NEW FOLDER:", nbuf) == 0) { return 0; }
        pjoin(dpath, cpath, nbuf);
        p = apnd(0, "mkdir "); p = apnd(p, dpath); run_op(); return 0;
    }
    if (op_target(&nm) == 0) { return 0; }              /* the selected entry, not ".." */
    if (kind == 2 && fdir[fsel]) { return 0; }          /* duplicate: files only */
    if (kind == 5) {                                    /* delete */
        if (confirm("DELETE THIS ITEM?") == 0) { return 0; }
        pjoin(vpath, cpath, nm);
        if (fdir[fsel]) { p = apnd(0, "rmdir "); } else { p = apnd(0, "del "); }
        p = apnd(p, vpath); run_op(); return 0;
    }
    if (kind == 1) { if (prompt_input("RENAME TO:", nbuf) == 0) { return 0; } }
    if (kind == 2) { if (prompt_input("DUPLICATE AS:", nbuf) == 0) { return 0; } }
    if (kind == 3) { if (prompt_input("MOVE TO DIR:", nbuf) == 0) { return 0; } }
    pjoin(vpath, cpath, nm);                            /* source */
    if (kind == 3) { pjoin(dpath, nbuf, nm); }          /* move: <typed dir>/<name> */
    else { pjoin(dpath, cpath, nbuf); }                 /* rename/dup: same dir, new name */
    if (kind == 2) { p = apnd(0, "cp "); } else { p = apnd(0, "mv "); }
    p = apnd(p, vpath); cmdbuf[p] = 32; p = p + 1; cmdbuf[p] = 0; p = apnd(p, dpath);
    run_op();
    return 0;
}

/* the FILE menu: a dropdown of the file operations, picked by their letter.
 * Each op prompts as needed and (on confirm) does NOT return -- it re-launches
 * the Finder through run_op; a cancel returns so the caller repaints. */
int file_menu() {
    int k;
    pen(65535); fillrect(58, 116, 258, 256);
    pen(0);     fillrect(60, 240, 256, 254);
    pen(65535); gtext(66, 244, "FILE");
    pen(0);
    gtext(66, 226, "R  RENAME");
    gtext(66, 214, "D  DUPLICATE");
    gtext(66, 202, "M  MOVE");
    gtext(66, 190, "N  NEW FOLDER");
    gtext(66, 178, "X  DELETE");
    gtext(66, 162, "ESC CANCEL");
    k = getkey();
    if (k == 'r' || k == 'R') { do_op(1); }
    if (k == 'd' || k == 'D') { do_op(2); }
    if (k == 'm' || k == 'M') { do_op(3); }
    if (k == 'n' || k == 'N') { do_op(4); }
    if (k == 'x' || k == 'X') { do_op(5); }
    return 0;
}

/* the right-click context menu: a popup at the cursor. has_item = a file/folder
 * was under the cursor (Open/Rename/Duplicate/Move/Delete on the selection);
 * otherwise the empty-desktop menu (New Folder). A click on a row runs that op
 * (which may not return -- it re-launches via run_op); a click outside, or any
 * key, dismisses. */
int ctx_menu(int mx, int my, int has_item) {
    int k; int row;
    if (mx > 340) { mx = 340; }                    /* keep the popup on screen */
    if (my < 90) { my = 90; }
    if (has_item) {
        pen(65535); fillrect(mx, my - 62, mx + 132, my);
        pen(0);
        gtext(mx + 6, my - 11, "OPEN");
        gtext(mx + 6, my - 23, "RENAME");
        gtext(mx + 6, my - 35, "DUPLICATE");
        gtext(mx + 6, my - 47, "MOVE");
        gtext(mx + 6, my - 59, "DELETE");
    } else {
        pen(65535); fillrect(mx, my - 14, mx + 132, my);
        pen(0);
        gtext(mx + 6, my - 11, "NEW FOLDER");
    }
    while (1) {
        k = ptr_ev();
        if (k == 1 || k == 4) {                    /* a click: on a row, or outside? */
            if (ptr_x >= mx && ptr_x <= mx + 132 && ptr_y <= my && ptr_y > my - 62) {
                row = (my - ptr_y) / 12;
                if (has_item == 0) { do_op(4); }       /* new folder */
                else if (row <= 0) { open_sel(); }
                else if (row == 1) { do_op(1); }       /* rename    */
                else if (row == 2) { do_op(2); }       /* duplicate */
                else if (row == 3) { do_op(3); }       /* move      */
                else { do_op(5); }                     /* delete    */
            }
            return 0;                              /* click (row or outside): dismiss */
        }
        if (k == 0) { return 0; }                  /* any key dismisses */
    }
    return 0;
}

int main() {
    int k; int going; int i; int ev; char *a;
    if (peek(GFXPRES) == 0) { puts("?No display"); return 1; }
    poke(GTSUSP, 1);                               /* claim the screen */
    gp(0x50); gp(0);                               /* TXEN 0: hide the text overlay */
    gsetup();                                      /* port + text projection */
    /* an absolute-path arg means we were RE-LAUNCHED by the auto-return script:
     * resume in that directory. Otherwise start at the CWD. */
    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == '/') {
        i = 0;
        while (a[i] != 0 && a[i] != 13 && a[i] != 10 && a[i] != 32 && i < 60) { cpath[i] = a[i]; i = i + 1; }
        cpath[i] = 0;
    } else {
        bios(SYS_GETCWD, cpath, 0);
    }
    if (cpath[0] == 0) { cpath[0] = '/'; cpath[1] = 0; }
    ptr_init();                                    /* keys + mouse on the console */
    ptr_motion();                                  /* 1003: free motion, for a following cursor */
    _curx = 240; _cury = 136; _curon = 0;          /* cursor starts centred */
    fscan();
    draw();
    going = 1;
    while (going) {
        ev = ptr_ev();
        if (ev == 1) {                             /* LEFT click: select, or open if
                                                      the click is on the selection */
            i = cell_at(ptr_x, ptr_y);
            if (cell_ok) { if (i == fsel) { open_sel(); } else { fsel = i; } }
        }
        else if (ev == 4) {                        /* RIGHT click: context menu */
            i = cell_at(ptr_x, ptr_y);
            if (cell_ok) { fsel = i; reveal(); draw(); ctx_menu(ptr_x, ptr_y, 1); }
            else { ctx_menu(ptr_x, ptr_y, 0); }
        }
        else if (ev == 5) {                        /* FREE move: just glide the cursor, no redraw */
            cur_to(ptr_x, ptr_y);
        }
        else if (ev == 0) {                        /* a key */
            k = ptr_key;
            if (k == 'q' || k == 'Q' || k == 27) { going = 0; }
            else if (k == 129 || k == 'j') { if (fsel + PGCOLS < fcnt) { fsel = fsel + PGCOLS; } } /* down a row */
            else if (k == 128 || k == 'k') { if (fsel >= PGCOLS) { fsel = fsel - PGCOLS; } }       /* up a row  */
            else if (k == 130 || k == 'l') { if (fsel < fcnt - 1) { fsel = fsel + 1; } }           /* right (lib_ptr: ESC[C=130) */
            else if (k == 131 || k == 'h') { if (fsel > 0) { fsel = fsel - 1; } }                  /* left  (lib_ptr: ESC[D=131) */
            else if (k == 13 || k == 10) { open_sel(); }                                           /* open      */
            else if (k == 8 || k == 127) { pup(); fscan(); }                                       /* up dir    */
            else if (k == 'a' || k == 'A') { apps_menu(); }
            else if (k == 'f' || k == 'F') { file_menu(); }
        }
        if (going && ev != 5) { reveal(); draw(); }   /* a free move never triggers a full redraw */
    }
    ptr_done();
    poke(GTSUSP, 0);                               /* release the console */
    return 0;
}
