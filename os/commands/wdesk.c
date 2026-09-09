/* wdesk.c -- the desktop CLIENT on the resident window-manager kernel.
 *
 * The window manager lives in the OS (os/wmkernel_body.asm, folded into
 * p8xos.asm; syscalls SYS_WKINIT..SYS_WKCLOSE). wdesk is the CLIENT: it
 * describes the desktop, draws its own MENU BAR, and drives the kernel one
 * event at a time with SYS_WKEVENT -- the split that keeps the OS tight
 * (the kernel is a small resident core) while the rich UI lives here, in
 * the 37 KB TPA. The kernel handles what it owns (TAB focus, arrows, mouse
 * press/drag/release -> raise/drag/close); it hands wdesk the keys it does
 * not own, and wdesk's menu bar acts on them.
 *
 * MENU BAR (the top 14 rows, drawn by this client, desk's look):
 *   L  launch paint          C  close the top window        Q  quit
 * The kernel keeps the windows alive across the launch, so pressing L
 * runs paint OVER wdesk and -- paint launched with -w -- quitting paint
 * re-execs "wdesk -r", which redraws the SAME resident windows AND this
 * menu bar. The desktop survives; nothing is reloaded.
 *
 * WINDOWS (all client-drawn where they carry live content -- the kernel
 * only hands over each window's rect via SYS_WKGET/SYS_WKTOP):
 *   SHAPES  a demo scene recorded into a card list (the card replays it)
 *   TERM    a real terminal: type a command and ENTER RUNS it with its
 *           OUTPUT rendered IN the window. wdesk arms the OS's OUTCH->window
 *           sink (SYS_WKSINK) at TERM's card list, writes a "<cmd>\nrun
 *           /bin/wdesk.bin -o" script and hands it to the shell (SYS_RUNSH);
 *           the command's stdout records into the list, and `wdesk -o`
 *           disarms + repaints so it appears. l/c/q TYPE here.
 *   FILES   a directory browser: n/p select, ENTER opens (navigate a dir,
 *           launch a .BIN, or show a .p8i in VIEW). Drawn while focused.
 *   VIEW    a picture window: opening a .p8i from FILES opens VIEW sized to
 *           the image (or re-fronts an existing one via SYS_WKRAISE) and
 *           streams the pixels in, one BLIT per row.
 *
 * Windows are addressed by TITLE letter (S/T/F/V), never by array index --
 * the kernel reorders records on a focus change (k_raise); the title is
 * stable. SYS_WKRAISE (a kernel z-order primitive) focuses a window by index.
 *
 * -r  RESUME: the windows are already in the kernel (a launched app is
 *     coming back), so skip init/open -- just redraw and re-enter the loop.
 *
 * Boot is unchanged -- monitor, B, shell -- this is opt-in by command. The
 * full standalone `desk` (its own in-TPA WM) is unaffected; this is the
 * kernel-backed successor, grown a rung at a time (docs/p8x-wm-design.md).
 */

//#use abi
//#use dirent

//#define GLDATA 0xFF50
//#define GLSTAT 0xFF51
//#define GFXPRES 0x60A4  /* two-mode flag: 1 = GL card fitted (monitor/OS set it) */

char param[22];
char frec[22];                     /* a window's record, read via SYS_WKGET */
char fnam[156];                    /* the FILES listing: up to 12 names x 13 */
char fdir[12];                     /* per entry: 1 = a directory */
char cpath[64];                    /* the FILES current directory path */
char fpath[68];                    /* scratch: a full path + " -w" to open */
int  fcnt;                         /* how many names are cached */
int  fsel;                         /* the selected row (0..fcnt-1) */

char tline[30];                    /* the TERM input line (being typed) */
int  tlen;                         /* length of the input line */

char vpath[68];                    /* the .p8i image the VIEW window shows */
int  vw;                           /* its pixel width  (from the header) */
int  vh;                           /* its pixel height */

/* Windows are identified by the FIRST LETTER of their title, NOT by array
 * index: the kernel PHYSICALLY REORDERS records when a window is raised
 * (k_raise), so an index does not track a given window across a focus change.
 * The title rides in the record (the kernel only displays it) and is stable.
 *   'S' SHAPES (kernel-drawn card list)  'T' TERM  'F' FILES  'V' VIEW  */

int gp(int v) { while (peek(GLSTAT) & 128) { } poke(GLDATA, v); return 0; }
int gw(int v) { gp(v & 255); gp((v / 256) & 255); return 0; }

/* stroke text at device (x,y): MOVE3 x y 0 then TEXT len chars. The kernel's
 * repaint leaves the GL in PROJCT 0 / MDIDEN / TSIZE / identity, so drawing
 * right after it needs no camera setup -- same idiom as the kernel's titles. */
int wtext(int x, int y, char *s) {
    int i;
    gp(18); gw(x); gw(y); gw(0);              /* MOVE3 x,y,0 */
    i = 0; while (s[i]) { i = i + 1; }
    gp(128); gp(i);                           /* TEXT <len> */
    i = 0; while (s[i]) { gp(s[i]); i = i + 1; }
    return 0;
}

/* the menu bar: a white strip across the top 14 rows with black CLICKABLE
 * words. Drawn after every kernel repaint (its FLOOD covers these rows too).
 * The words sit at columns that match the click zones in act_at() below:
 * PAINT ~col 11, CLOSE ~col 26, QUIT ~col 41. The keys L/C/Q do the same. */
int menubar() {
    gp(224); gp(1);                           /* PRMFIL 1 (filled)     */
    gp(6); gp(31); gp(63); gp(31);            /* COLOR white           */
    gp(16); gw(0); gw(258);                   /* MOVE 0,258            */
    gp(52); gw(479); gw(271);                 /* RECT: the bar         */
    gp(224); gp(0);                           /* PRMFIL 0              */
    gp(6); gp(0); gp(0); gp(0);               /* COLOR black           */
    wtext(6,   261, "DESK");                  /* the label (not clickable) */
    wtext(60,  261, "PAINT");
    wtext(150, 261, "CLOSE");
    wtext(240, 261, "QUIT");
    return 0;
}

/* run a menu action: 0 = launch paint, 1 = close top, 2 = quit. Returns 1
 * when the caller should quit. Shared by the L/C/Q keys and the bar clicks. */
int act(int a) {
    if (a == 0) {
        bios(SYS_EXEC, "/bin/paint.bin -w", 0);   /* becomes paint; no return */
        redraw();                                 /* only if exec failed */
        return 0;
    }
    if (a == 1) {
        bios(SYS_WKCLOSE, 0, 0);
        bios(SYS_WKREPAINT, 0, 0);
        redraw();
        return 0;
    }
    return 1;                                     /* a == 2: quit */
}

/* map a menu-bar click COLUMN to an action, or 99 for the DESK label / gaps
 * (99 not -1: p8cc compares are unsigned, so a -1 would test as a valid < 3) */
int act_at(int col) {
    if (col >= 8 && col < 20) { return 0; }       /* PAINT */
    if (col >= 20 && col < 36) { return 1; }      /* CLOSE */
    if (col >= 36) { return 2; }                  /* QUIT */
    return 99;                                    /* the label, or a gap */
}

/* reset WINDOW + VWPORT to the full screen (identity) -- the kernel leaves
 * this after a repaint; a client that changes it (to draw window content)
 * must restore it before drawing anything full-screen (the menu bar). */
int camfull() {
    gp(179); gw(0); gw(479); gw(0); gw(271);  /* WINDOW  0..479, 0..271 */
    gp(178); gw(0); gw(479); gw(0); gw(271);  /* VWPORT  identity        */
    return 0;
}

/* read the current directory into fnam[] once (not per repaint -- disk is
 * slow). Keeps files/dirs with a printable name; skips '.', deleted slots
 * and the volume label, the way desk's FILES does. */
int files_scan() {
    int r; int j; int k;
    fcnt = 0; fsel = 0;
    r = bios(FOPENDIR, cpath, 0);
    if (r & 256) { return 1; }
    r = bios(FNEXT, 0, 0);
    while ((r & 256) == 0 && fcnt < 12) {
        de_read();
        j = de[0] & 255;                          /* keep files/dirs with a
                                                     printable name, and '..',
                                                     but skip '.', deleted slots
                                                     and the volume label */
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

/* draw the cached listing INSIDE the FILES window body. The caller has already
 * fetched the focused window's record into frec[] and dispatched here because it
 * is the FILES window; content_draw() draws only the FOCUSED window, so this
 * overlay (after the kernel's repaint) correctly sits on top. WINDOW/VWPORT map
 * the body to window-LOCAL coords (the card clips to it), desk's lib_wm idiom. */
int files_body() {
    int x; int y; int w; int h; int cw; int ch; int row; int j; int k; char *s;
    x = (frec[0]&255) + (frec[1]&255)*256;
    y = (frec[2]&255) + (frec[3]&255)*256;
    w = (frec[4]&255) + (frec[5]&255)*256;
    h = (frec[6]&255) + (frec[7]&255)*256;
    cw = w - 2; ch = h - 15;
    gp(179); gw(0); gw(cw-1); gw(0); gw(ch-1);              /* WINDOW local  */
    gp(178); gw(x+1); gw(x+cw); gw(271-(y+ch)); gw(271-(y+1)); /* VWPORT rect */
    row = 0;
    while (row < fcnt) {
        if (row == fsel) { gp(6); gp(31); gp(63); gp(0); }        /* selected: yellow */
        else if (fdir[row]) { gp(6); gp(0); gp(63); gp(31); }     /* a dir: cyan */
        else { gp(6); gp(31); gp(63); gp(31); }                   /* a file: white */
        s = fnam + row*13;
        k = 0; while (s[k]) { k = k + 1; }
        gp(18); gw(4); gw(ch - 13 - row*13); gw(0);        /* MOVE3 x,y,0   */
        gp(128); gp(k);                                    /* TEXT <len>    */
        j = 0; while (j < k) { gp(s[j]); j = j + 1; }
        row = row + 1;
    }
    camfull();                                             /* restore identity */
    return 0;
}

/* --- path helpers (from desk) + FILES open ---------------------------------- */
int scopy(char *d, char *c, int cap) { int i; i=0; while (c[i] && i<cap) { d[i]=c[i]; i=i+1; } d[i]=0; return 0; }

int pjoin(char *out, char *dir, char *leaf) {          /* out = dir + "/" + leaf */
    int i; int jj;
    i=0; while (dir[i]) { out[i]=dir[i]; i=i+1; }
    if (i > 1) { out[i]='/'; i=i+1; }                  /* "/" needs no extra slash */
    jj=0; while (leaf[jj]) { out[i]=leaf[jj]; i=i+1; jj=jj+1; }
    out[i]=0; return 0;
}

int pup() {                                            /* cpath: strip a component */
    int r; r=0; while (cpath[r]) { r=r+1; }
    while (r > 1 && cpath[r] != '/') { r=r-1; }
    if (r == 0) { r=1; }
    cpath[r]=0;
    if (cpath[1]==0) { cpath[0]='/'; cpath[1]=0; }
    return 0;
}

int ftype(char *s) {                                   /* 1 = .P8I, 2 = .BIN (case-blind) */
    int n; n=0; while (s[n]) { n=n+1; }
    if (n < 4) { return 0; }
    if (s[n-4] != '.') { return 0; }
    if ((s[n-3]&95)=='P' && s[n-2]=='8' && (s[n-1]&95)=='I') { return 1; }
    if ((s[n-3]&95)=='B' && (s[n-2]&95)=='I' && (s[n-1]&95)=='N') { return 2; }
    return 0;
}

/* append " -w" to a path and launch it. SYS_EXEC BECOMES the program, so on
 * success this never returns; the -w tells a WM-aware app (paint, wdesk) to
 * resume this desktop on quit. Returns 1 only if the exec failed. Shared by
 * the FILES opener and the TERM command line. */
int launchw(char *p) {
    int j;
    j = 0; while (p[j]) { j = j + 1; }
    p[j]=' '; p[j+1]='-'; p[j+2]='w'; p[j+3]=0;
    bios(SYS_EXEC, p, 0);
    return 1;
}

/* find an open window by its title letter -> its CURRENT index, or 99 if none.
 * Indices shift as windows are raised, so this scans every slot each time (the
 * counterpart to title-dispatch: it is how the client turns a title back into
 * the index SYS_WKRAISE needs). Clobbers frec[]. */
int win_index(int letter) {
    int i; int top;
    top = bios(SYS_WKTOP, 0, 0);                        /* = wcnt-1, or 99 */
    if (top == 99) { return 99; }
    i = 0;
    while (i <= top) {
        bios(SYS_WKGET, frec, i);
        if ((frec[10]&255) == letter) { return i; }
        i = i + 1;
    }
    return 99;
}

/* open a .p8i into the VIEW window. Reads the 10-byte header for the picture
 * size, then opens VIEW sized to it (the 4th window -> added on top, focused)
 * or -- if a VIEW window already exists -- RAISES it (SYS_WKRAISE) and reuses
 * it. view_body() streams the pixels on each repaint while VIEW is focused. */
int view_open(char *nm) {
    int w2; int h2; int vi;
    pjoin(vpath, cpath, nm);
    bios(FRESOLVE, vpath, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { vpath[0]=0; return 0; }
    bios(FGETB,0,0); bios(FGETB,0,0);                  /* P 8            */
    bios(FGETB,0,0); bios(FGETB,0,0);                  /* I version      */
    w2 = bios(FGETB,0,0)&255; w2 = w2 + (bios(FGETB,0,0)&255)*256;
    h2 = bios(FGETB,0,0)&255; h2 = h2 + (bios(FGETB,0,0)&255)*256;
    if (w2==0 || h2==0 || w2>456 || h2>240) { vpath[0]=0; return 0; }
    vw = w2; vh = h2;
    vi = win_index('V');
    if (vi == 99) { setw(20, 20, w2+2, h2+15, 0, "VIEW"); }  /* open it (4th) */
    else { bios(SYS_WKRAISE, 0, vi); }                       /* re-front it   */
    bios(SYS_WKREPAINT, 0, 0);
    redraw();
    return 0;
}

/* open the selected entry: navigate a directory, or launch a .BIN (chained
 * with -w so a WM-aware app resumes the desktop; others just exit to the shell) */
int files_open() {
    char *nm; int t;
    if (fsel >= fcnt) { return 0; }
    nm = fnam + fsel*13;
    if (fdir[fsel]) {
        if (nm[0]=='.') { pup(); }                     /* ".." -> up */
        else { pjoin(fpath, cpath, nm); scopy(cpath, fpath, 60); }
        files_scan();
        return 0;
    }
    t = ftype(nm);
    if (t == 2) {                                      /* a .BIN -> launch it */
        pjoin(fpath, cpath, nm);
        launchw(fpath);                                /* becomes it; no return */
    }
    else if (t == 1) { view_open(nm); }                /* a .p8i -> show in VIEW */
    return 0;                                          /* anything else: ignore */
}

/* FILES key handling (only when FILES is the focused window): n/p move the
 * selection, ENTER opens. Returns 1 if the caller must redraw. */
int files_key(int key) {
    if (key==110 && fsel+1 < fcnt) { fsel=fsel+1; return 1; }      /* n = next */
    if (key==112 && fsel > 0)      { fsel=fsel-1; return 1; }      /* p = prev */
    if (key==13 || key==10)        { files_open(); return 1; }     /* ENTER   */
    return 0;
}

/* --- TERM: a command line whose output goes INTO the window via the sink ----- */

/* draw the TERM INPUT LINE at the bottom of the window body. The command OUTPUT
 * is no longer client-drawn -- it lives in the window's card list (id TLIST),
 * recorded there by the OUTCH->window sink and replayed by the kernel's CLRUN on
 * repaint. So this only overlays the prompt "$ <line>_" the user is typing, near
 * the bottom (y small, y-up local) so it clears the output above it. */
int term_body() {
    int x; int y; int w; int h; int cw; int ch; int j;
    x = (frec[0]&255) + (frec[1]&255)*256;
    y = (frec[2]&255) + (frec[3]&255)*256;
    w = (frec[4]&255) + (frec[5]&255)*256;
    h = (frec[6]&255) + (frec[7]&255)*256;
    cw = w - 2; ch = h - 15;
    gp(179); gw(0); gw(cw-1); gw(0); gw(ch-1);                 /* WINDOW local  */
    gp(178); gw(x+1); gw(x+cw); gw(271-(y+ch)); gw(271-(y+1)); /* VWPORT rect   */
    gp(6); gp(31); gp(63); gp(0);                              /* yellow prompt */
    gp(18); gw(4); gw(4); gw(0);                               /* bottom line   */
    gp(128); gp(tlen+3);                                       /* "$ " + line + _ */
    gp('$'); gp(' ');
    j = 0; while (j < tlen) { gp(tline[j]); j = j + 1; }
    gp('_');
    camfull();
    return 0;
}

/* write /TERM.SCR = "<cmd>\nrun /bin/wdesk.bin -o\n": run the typed command, then
 * re-launch wdesk in resume mode. The command's stdout is recorded into the TERM
 * window (the sink was armed just before); `wdesk -o` disarms and repaints. */
int write_script(char *cmd) {
    int i; char *r;
    bios(FRESOLVE, "/TERM.SCR", 0);
    bios(FDELETE, "/TERM.SCR", 0);                     /* replace any old one */
    bios(FRESOLVE, "/TERM.SCR", 0);
    bios(FWOPEN, 0, 0);
    i=0; while (cmd[i]) { bios(FPUTB, 0, cmd[i]); i=i+1; }
    bios(FPUTB, 0, 10);
    r = "run /bin/wdesk.bin -o";
    i=0; while (r[i]) { bios(FPUTB, 0, r[i]); i=i+1; }
    bios(FPUTB, 0, 10);
    bios(FCLOSE, 0, 0);
    return 0;
}

/* run the typed command with its output going INTO the TERM window: arm the sink
 * at the TERM window (found by title, since indices shift), write the two-line
 * script, and hand it to the shell (SYS_RUNSH -- does not return; the script's
 * `wdesk -o` brings the desktop back with the output on the card). */
int term_run(char *cmd) {
    int ti;
    ti = win_index('T');
    if (ti == 99) { return 0; }
    bios(SYS_WKSINK, 0, ti);                           /* arm: stdout -> TERM list */
    write_script(cmd);
    bios(SYS_RUNSH, "/TERM.SCR", 0);                   /* run it; no return */
    return 0;
}

/* TERM key handling (only when TERM is focused): printable keys type into the
 * line, BACKSPACE deletes, ENTER runs it with output in the window. Returns 1
 * when the caller must redraw. */
int term_key(int key) {
    if (key==13 || key==10) {                          /* ENTER: run the line */
        if (tlen > 0) { tline[tlen]=0; term_run(tline); }   /* no return on run */
        tlen = 0; tline[0]=0;
        return 1;
    }
    if ((key==8 || key==127) && tlen > 0) { tlen=tlen-1; tline[tlen]=0; return 1; }
    if (key>=32 && key<=126 && tlen < 28) { tline[tlen]=key; tlen=tlen+1; tline[tlen]=0; return 1; }
    return 0;
}

/* stream the .p8i into the VIEW window body: skip the 10-byte header, then one
 * BLIT per row (bytes streamed verbatim), anchored in window-LOCAL coords so the
 * picture rides wherever the window is dragged -- desk's drawview, into a kernel
 * window. Re-read from disk each repaint (no framebuffer), exactly as desk does. */
int view_body() {
    int x; int y; int w; int h; int cw; int ch; int py; int n; int r;
    x = (frec[0]&255) + (frec[1]&255)*256;
    y = (frec[2]&255) + (frec[3]&255)*256;
    w = (frec[4]&255) + (frec[5]&255)*256;
    h = (frec[6]&255) + (frec[7]&255)*256;
    cw = w - 2; ch = h - 15;
    gp(179); gw(0); gw(cw-1); gw(0); gw(ch-1);                 /* WINDOW local  */
    gp(178); gw(x+1); gw(x+cw); gw(271-(y+ch)); gw(271-(y+1)); /* VWPORT rect   */
    if (vpath[0] == 0) {                                       /* nothing loaded */
        gp(6); gp(31); gp(63); gp(31);
        gp(18); gw(4); gw(ch-13); gw(0);
        gp(128); gp(16); gp('o'); gp('p'); gp('e'); gp('n'); gp(' ');
        gp('a'); gp(' '); gp('.'); gp('p'); gp('8'); gp('i'); gp(' ');
        gp('i'); gp('n'); gp(' '); gp('F');
        camfull(); return 0;
    }
    bios(FRESOLVE, vpath, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { camfull(); return 0; }
    py = 0; while (py < 10) { bios(FGETB, 0, 0); py = py + 1; }   /* the header */
    py = 0;
    while (py < vh) {
        gp(100); gw(0); gw(vh-1-py); gw(vw); gw(1);            /* BLIT 0,y,vw,1 */
        n = vw + vw;                                           /* 2 bytes/pixel */
        while (n) {
            r = bios(FGETB, 0, 0);
            if (r & 256) { gp(0); } else { gp(r & 255); }
            n = n - 1;
        }
        py = py + 1;
    }
    camfull();
    return 0;
}

/* draw the FOCUSED window's client content. Reads the top window's record and
 * dispatches on its title letter -- only the focused window gets client content,
 * so the overlay never paints over a window stacked above it. Windows the kernel
 * draws itself (SHAPES, a card list) need nothing here. */
int content_draw() {
    int top;
    top = bios(SYS_WKTOP, 0, 0);
    bios(SYS_WKGET, frec, top);
    if ((frec[10]&255) == 'T') { term_body(); }
    else if ((frec[10]&255) == 'F') { files_body(); }
    else if ((frec[10]&255) == 'V') { view_body(); }
    return 0;
}

/* redraw the client's own layers on top of the kernel's window repaint */
int redraw() { menubar(); content_draw(); return 0; }

/* one 22-byte window record -> SYS_WKOPEN */
int setw(int x, int y, int w, int h, int list, char *t) {
    int i;
    param[0]=x&255; param[1]=(x/256)&255;
    param[2]=y&255; param[3]=(y/256)&255;
    param[4]=w&255; param[5]=(w/256)&255;
    param[6]=h&255; param[7]=(h/256)&255;
    param[8]=list;
    i=0; while (t[i] && i<12) { param[10+i]=t[i]; i=i+1; }
    param[9]=i;
    while (i<12) { param[10+i]=0; i=i+1; }
    bios(SYS_WKOPEN, param, 0);
    return 0;
}

/* SHAPES' scene -> card list 30, window-LOCAL coords: a red frame + a filled
 * yellow box that overruns the edge (the card clips it). Re-recorded on every
 * entry (including -r) so it is correct whatever a launched app did with the
 * card's lists. Card lists persist, so a repaint replays it in two wire bytes. */
int scene() {
    gp(112); gp(30);                          /* CLBEG 30              */
    gp(224); gp(0);
    gp(6); gp(31); gp(0); gp(0);              /* COLOR red             */
    gp(16); gw(10); gw(10);
    gp(52); gw(198); gw(125);
    gp(224); gp(1);
    gp(6); gp(31); gp(63); gp(0);             /* COLOR yellow          */
    gp(16); gw(150); gw(90);
    gp(52); gw(260); gw(180);                 /* overrun -> clipped    */
    gp(224); gp(0);
    gp(113);                                  /* CLEND                 */
    return 0;
}

int main() {
    char *ap; int k; int going; int e; int a; int top; int resume;
    if (peek(GFXPRES) == 0) { puts("?No display"); return 1; }
    ap = argstr();
    while (*ap == 32) { ap = ap + 1; }
    /* -r = a launched app is returning; -o = a TERM sink command is returning
     * (disarm the sink first). Both RESUME: the windows are already resident. */
    resume = (ap[0] == '-' && (ap[1] == 'r' || ap[1] == 'o'));
    if (ap[0] == '-' && ap[1] == 'o') { bios(SYS_WKSINK, 0, 255); }

    cpath[0] = '/'; cpath[1] = 0;             /* FILES starts at the root */
    scene();                                  /* card list 30, always */
    files_scan();                             /* read the CWD into fnam[] */
    if (!resume) {                            /* fresh: open the windows */
        bios(SYS_WKINIT, 0, 0);
        setw(40, 40, 210, 150, 30, "SHAPES"); /* kernel-drawn card list 30 */
        setw(70, 100, 300, 150, 31, "TERM");  /* output = card list 31 (the sink) */
        setw(190, 60, 240, 170, 0, "FILES");  /* opened last -> top, listing shows */
        gp(112); gp(31); gp(113);             /* define list 31 empty (CLRUN-safe) */
    }
    bios(SYS_WKREPAINT, 0, 0);
    redraw();                                 /* menu bar + focused content */
    puts("WDESK (man wdesk)");

    going = 1;
    while (going) {
        e = bios(SYS_WKEVENT, 0, 0);          /* one event */
        if (e & 256) { going = 0; }           /* carry -> quit (^D) */
        else if (e == 0) { redraw(); }        /* kernel repainted -> our layers */
        else if (e == 1) {                    /* an unowned key */
            k = bios(SYS_WKARG, 0, 0);
            top = bios(SYS_WKTOP, 0, 0);
            bios(SYS_WKGET, frec, top);        /* who is focused? (by title) */
            if ((frec[10]&255) == 'T') {       /* TERM focused: it owns the whole
                                                  keyboard, so l/c/q type here */
                if (term_key(k)) { redraw(); }
            } else {
                a = 99;                        /* 99 = not a menu key (p8cc
                                                  compares are UNSIGNED, so a
                                                  -1 sentinel tests as >= 0) */
                if (k == 108 || k == 76) { a = 0; }        /* L = paint  */
                else if (k == 99 || k == 67) { a = 1; }    /* C = close  */
                else if (k == 113 || k == 81) { a = 2; }   /* Q = quit   */
                if (a < 3) { if (act(a)) { going = 0; } }  /* a menu action */
                else if ((frec[10]&255) == 'F') {          /* else FILES nav */
                    if (files_key(k)) { redraw(); }        /* n/p/ENTER */
                }
            }
        }
        else if (e == 2) {                    /* a menu-bar click */
            a = act_at(bios(SYS_WKARG, 0, 0));
            if (a < 3 && act(a)) { going = 0; }
        }
    }

    gp(116); gp(30);                          /* CLDEL 30: tidy the card */
    while (peek(GLSTAT) & 64) { }
    puts("bye");
    return 0;
}
