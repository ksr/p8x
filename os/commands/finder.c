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
    gtext(206, 261, "F FILE  A APPS  ENTER OPEN  BKSP UP  Q QUIT");
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

/* rename the selected entry (mv within the same directory) */
int op_rename() {
    char *nm; int p;
    if (op_target(&nm) == 0) { return 0; }
    if (prompt_input("RENAME TO:", nbuf) == 0) { return 0; }
    pjoin(vpath, cpath, nm);                            /* source */
    pjoin(dpath, cpath, nbuf);                          /* dest (same dir) */
    p = apnd(0, "mv "); p = apnd(p, vpath);
    cmdbuf[p] = 32; p = p + 1; cmdbuf[p] = 0;
    p = apnd(p, dpath);
    run_op();
    return 0;
}

/* duplicate the selected FILE (cp to a new name in the same directory) */
int op_dup() {
    char *nm; int p;
    if (op_target(&nm) == 0) { return 0; }
    if (fdir[fsel]) { return 0; }                       /* files only (cp -r is heavy) */
    if (prompt_input("DUPLICATE AS:", nbuf) == 0) { return 0; }
    pjoin(vpath, cpath, nm);
    pjoin(dpath, cpath, nbuf);
    p = apnd(0, "cp "); p = apnd(p, vpath);
    cmdbuf[p] = 32; p = p + 1; cmdbuf[p] = 0;
    p = apnd(p, dpath);
    run_op();
    return 0;
}

/* move the selected entry into another directory (an absolute dir path typed in) */
int op_move() {
    char *nm; int p;
    if (op_target(&nm) == 0) { return 0; }
    if (prompt_input("MOVE TO DIR:", nbuf) == 0) { return 0; }
    pjoin(vpath, cpath, nm);                            /* source */
    pjoin(dpath, nbuf, nm);                             /* dest = <typed dir>/<name> */
    p = apnd(0, "mv "); p = apnd(p, vpath);
    cmdbuf[p] = 32; p = p + 1; cmdbuf[p] = 0;
    p = apnd(p, dpath);
    run_op();
    return 0;
}

/* make a new folder in the current directory */
int op_newdir() {
    int p;
    if (prompt_input("NEW FOLDER:", nbuf) == 0) { return 0; }
    pjoin(dpath, cpath, nbuf);
    p = apnd(0, "mkdir "); p = apnd(p, dpath);
    run_op();
    return 0;
}

/* delete the selected entry (del for a file, rmdir for an empty directory) */
int op_delete() {
    char *nm; int p;
    if (op_target(&nm) == 0) { return 0; }
    if (confirm("DELETE THIS ITEM?") == 0) { return 0; }
    pjoin(vpath, cpath, nm);
    if (fdir[fsel]) { p = apnd(0, "rmdir "); }          /* directory: must be empty */
    else { p = apnd(0, "del "); }                       /* file */
    p = apnd(p, vpath);
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
    if (k == 'r' || k == 'R') { op_rename(); }
    if (k == 'd' || k == 'D') { op_dup(); }
    if (k == 'm' || k == 'M') { op_move(); }
    if (k == 'n' || k == 'N') { op_newdir(); }
    if (k == 'x' || k == 'X') { op_delete(); }
    return 0;
}

int main() {
    int k; int going; int i; char *a;
    if (peek(GFXPRES) == 0) { puts("?No display"); return 1; }
    poke(GTSUSP, 1);                               /* claim the screen */
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
        else if (k == 'a' || k == 'A') { apps_menu(); }                                /* APPS menu */
        else if (k == 'f' || k == 'F') { file_menu(); }                                /* FILE menu */
        if (going) { reveal(); draw(); }
    }
    poke(GTSUSP, 0);                               /* release the console */
    return 0;
}
