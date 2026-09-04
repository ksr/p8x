/* paint.c -- a keyboard-driven vector paint program for the GL card.
 *
 * The drawing is a DISPLAY LIST: every committed shape (line, box,
 * circle, fill) is recorded, so erase pops the last shape and the
 * canvas replays -- the vector-editor model, matching the card's own
 * philosophy (a scene is commands, not pixels).
 *
 * The screen splits into a PALETTE strip (top, drawn once with the
 * full-screen viewport) and the CANVAS. After the palette is up, the
 * VIEWPORT is clamped to the canvas, so the CARD clips every stroke,
 * fill and rubber-band -- nothing can ever paint over the palette.
 *
 * Interaction is pure PGC idiom:
 *   - the crosshair cursor and rubber-band ghosts draw in LINFUN 1
 *     (complement): drawing the same thing twice restores the screen
 *     exactly, over any background, at any pen. Solid commits go back
 *     to LINFUN 0.
 *   - fill is AREABC: a PIXELR ray walks right from the drop point to
 *     find the enclosing outline's colour, which becomes the boundary
 *     colour; the fill itself is the selected pen.
 *
 * Keys: w/a/s/d move (1 px), W/A/S/D move (8 px), arrows move (4 px);
 * l/b/c/f pick the tool, 1-8 the colour; SPACE anchors then commits;
 * x cancels a rubber-band; e (or u) erases the last shape; n clears;
 * q quits. Status echoes on the serial console.
 *
 * THE MOUSE comes through the same console via lib_ptr (//#use ptr),
 * which enables xterm mouse tracking, so a supporting terminal
 * reports press/drag/release as escape sequences on CONIN. Press
 * moves the crosshair and anchors (or drops, for fill), drag rubber-
 * bands live, release commits; a click on the palette strip selects a
 * swatch or tool; right-click cancels. Terminal cells map onto the
 * panel through the size the terminal reports to ESC[18t (80x24
 * assumed if it stays silent -- probed with CONST, never a blocking
 * read). A terminal without mouse reporting ignores the enables and
 * the keyboard drives everything, as before.
 */

//#use abi
//#use ptr

//#define GLDATA 0xFF50
//#define GLSTAT 0xFF51
//#define GLRB   0xFF52
//#define GLID   0xFF54

/* ---- the display list: 6 ints per shape, flat ------------------------------
 * [tool, x0, y0, x1, y1, colour]; tool 0=line 1=box 2=circle 3=fill.
 * line/box: two corners. circle: centre + r in x1 (y1 unused).
 * fill: seed point + boundary colour in x1. */
int sh[900];                       /* 150 shapes */
int nsh;

int tool;                          /* 0 line, 1 box, 2 circle, 3 fill */
int col;                           /* 0..7 into the palette */
int cx; int cy;                    /* cursor, window coords (y UP) */
int ax; int ay;                    /* rubber-band anchor */
int armed;                         /* anchor placed, ghost live */

/* the 8 pens, RGB565 */
int pal[8];

int mdown;                         /* a mouse press is being dragged */

/* ---- GL emission ----------------------------------------------------------- */
int gput(int v) {
    while (peek(GLSTAT) & 128) { }
    poke(GLDATA, v);
    return 0;
}
int gw(int v) { gput(v & 255); gput((v / 256) & 255); return 0; }
int gwait() { while (peek(GLSTAT) & 64) { } return 0; }

int pen(int c) {                              /* COLOR, unpacked 565 */
    gput(6); gput((c >> 11) & 31); gput((c >> 5) & 63); gput(c & 31);
    return 0;
}
int mode(int m) { gput(235); gput(m); return 0; }     /* LINFUN */
int fillm(int f) { gput(224); gput(f); return 0; }    /* PRMFIL */
int mov(int x, int y) { gput(16); gw(x); gw(y); return 0; }

int pixelr(int x, int y) {                    /* PIXRD via the RB FIFO */
    int lo;
    gput(99); gw(x); gw(y);
    while ((peek(GLSTAT) & 1) == 0) { }
    lo = peek(GLRB);
    while ((peek(GLSTAT) & 1) == 0) { }
    return lo | (peek(GLRB) << 8);
}

/* Full-screen vs canvas mapping. WINDOW and VWPORT move TOGETHER so the
 * map stays 1:1 -- then the WINDOW edge is a pure CLIP, and the canvas
 * setting makes the card itself keep every stroke, ghost and fill off
 * the palette strip. (A viewport alone would REMAP, not clip.) */
int vp_all() {
    gput(179); gw(0); gw(479); gw(0); gw(271);
    gput(178); gw(0); gw(479); gw(0); gw(271);
    return 0;
}
int vp_canvas() {
    /* VWPORT y is in top-down DEVICE rows (py = vy2 - (y-wy1)*scale), so
     * identity-with-clip pairs WINDOW y 0..244 with VWPORT rows 27..271:
     * window wy w lands on device row 271-w exactly, strokes clip at
     * wy 244, and FLOOD stops at row 27 -- the palette rows are safe. */
    gput(179); gw(0); gw(479); gw(0); gw(244);
    gput(178); gw(0); gw(479); gw(27); gw(271);
    return 0;
}

/* ---- console status (outc/outs/rawkey live in lib_ptr) ---------------------- */
int status() {
    outc(13);
    if (tool == 0) { outs("LINE  "); }
    if (tool == 1) { outs("BOX   "); }
    if (tool == 2) { outs("CIRCLE"); }
    if (tool == 3) { outs("FILL  "); }
    outc(32);
    if (col == 0) { outs("WHITE  "); }
    if (col == 1) { outs("RED    "); }
    if (col == 2) { outs("GREEN  "); }
    if (col == 3) { outs("BLUE   "); }
    if (col == 4) { outs("YELLOW "); }
    if (col == 5) { outs("CYAN   "); }
    if (col == 6) { outs("MAGENTA"); }
    if (col == 7) { outs("ORANGE "); }
    if (armed) { outs(" [anchored]"); } else { outs("           "); }
    return 0;
}

/* ---- the crosshair and ghosts (all complement mode) ------------------------ */
int cross() {                                 /* self-inverse: call to draw,
                                                 call again to erase */
    mode(1);
    mov(cx - 4, cy); gput(40); gw(cx + 4); gw(cy);
    mov(cx, cy - 4); gput(40); gw(cx); gw(cy + 4);
    mode(0);
    return 0;
}

int rmax(int dx, int dy) {                    /* circle radius: max(|dx|,|dy|).
                                                 p8cc compares are UNSIGNED, so
                                                 "negative" = wrapped-huge */
    if (dx > 30000) { dx = 0 - dx; }
    if (dy > 30000) { dy = 0 - dy; }
    if (dx < dy) { return dy; }
    return dx;
}

int ghost() {                                 /* the rubber-band, self-inverse */
    mode(1);
    if (tool == 0) { mov(ax, ay); gput(40); gw(cx); gw(cy); }
    if (tool == 1) { mov(ax, ay); gput(52); gw(cx); gw(cy); }
    if (tool == 2) { mov(ax, ay); gput(56); gw(rmax(cx - ax, cy - ay)); }
    mode(0);
    return 0;
}

/* ---- solid drawing (used by commit and by replay) -------------------------- */
int solid(int t, int x0, int y0, int x1, int y1, int c) {
    pen(c);
    if (t == 0) { mov(x0, y0); gput(40); gw(x1); gw(y1); }
    if (t == 1) { mov(x0, y0); gput(52); gw(x1); gw(y1); }
    if (t == 2) { mov(x0, y0); gput(56); gw(x1); }
    if (t == 3) {                             /* AREABC: pen fills, x1 bounds */
        mov(x0, y0);
        gput(193); gput((x1 >> 11) & 31); gput((x1 >> 5) & 63); gput(x1 & 31);
    }
    return 0;
}

int replay() {                                /* erase/clear: FLOOD the canvas
                                                 viewport, then the whole list */
    int i;
    gput(7); gput(0); gput(0); gput(0);       /* FLOOD black (canvas only) */
    i = 0;
    while (i < nsh) {
        solid(sh[i * 6], sh[i * 6 + 1], sh[i * 6 + 2],
              sh[i * 6 + 3], sh[i * 6 + 4], sh[i * 6 + 5]);
        i = i + 1;
    }
    return 0;
}

/* ---- the palette strip (full viewport; drawn once) ------------------------- */
int swx(int i) { return 6 + i * 26; }         /* swatch i left edge */
int tcx(int j) { return 230 + j * 30; }       /* tool cell j left edge */

int selbox(int x, int w, int on) {            /* selection bracket */
    if (on) { pen(65535); } else { pen(0); }
    mov(x - 2, 250); gput(52); gw(x + w + 1); gw(269);
    return 0;
}

int palette() {
    int i;
    vp_all();
    pen(65535);                               /* separator */
    mov(0, 246); gput(40); gw(479); gw(246);
    i = 0;                                    /* 8 swatches, filled */
    while (i < 8) {
        pen(pal[i]); fillm(1);
        mov(swx(i), 252); gput(52); gw(swx(i) + 20); gw(267);
        fillm(0);
        i = i + 1;
    }
    pen(65535);                               /* tool glyphs, in miniature */
    mov(tcx(0) + 2, 254); gput(40); gw(tcx(0) + 22); gw(265);   /* line  */
    mov(tcx(1) + 4, 254); gput(52); gw(tcx(1) + 20); gw(265);   /* box   */
    mov(tcx(2) + 12, 259); gput(56); gw(6);                     /* circle*/
    fillm(1);                                                   /* fill: */
    mov(tcx(3) + 12, 258); gput(56); gw(4);                     /*  drop */
    fillm(0);
    selbox(swx(col), 20, 1);
    selbox(tcx(tool), 24, 1);
    vp_canvas();
    return 0;
}

int pick_col(int c) {
    vp_all(); selbox(swx(col), 20, 0);
    col = c;  selbox(swx(col), 20, 1);
    vp_canvas();
    status();
    return 0;
}
int pick_tool(int t) {
    if (armed) { ghost(); armed = 0; }        /* drop a live rubber-band */
    vp_all(); selbox(tcx(tool), 24, 0);
    tool = t; selbox(tcx(tool), 24, 1);
    vp_canvas();
    status();
    return 0;
}

/* ---- fill: probe right for the enclosing boundary's colour ----------------- */
int drop() {
    int x; int bc;
    if (nsh >= 150) { return 0; }
    if (pixelr(cx, cy) != 0) { return 0; }    /* must start on background */
    x = cx + 1; bc = 0;
    while (x < 480) {
        bc = pixelr(x, cy);
        if (bc != 0) { x = 480; } else { x = x + 1; }
    }
    if (bc == 0) { return 0; }                /* open to the right: refuse */
    sh[nsh * 6] = 3;     sh[nsh * 6 + 1] = cx; sh[nsh * 6 + 2] = cy;
    sh[nsh * 6 + 3] = bc; sh[nsh * 6 + 4] = 0; sh[nsh * 6 + 5] = pal[col];
    solid(3, cx, cy, bc, 0, pal[col]);
    nsh = nsh + 1;
    return 0;
}

/* ---- commit the armed shape ------------------------------------------------ */
int commit() {
    int x1; int y1;
    if (nsh >= 150) { armed = 0; return 0; }
    x1 = cx; y1 = cy;
    if (tool == 2) { x1 = rmax(cx - ax, cy - ay); y1 = 0; }
    sh[nsh * 6] = tool;  sh[nsh * 6 + 1] = ax; sh[nsh * 6 + 2] = ay;
    sh[nsh * 6 + 3] = x1; sh[nsh * 6 + 4] = y1; sh[nsh * 6 + 5] = pal[col];
    solid(tool, ax, ay, x1, y1, pal[col]);
    nsh = nsh + 1;
    return 0;
}

/* ---- cursor movement (clamped inside the canvas) --------------------------- */
int mvcur(int dx, int dy) {
    cross();                                  /* erase */
    if (armed && tool != 3) { ghost(); }      /* erase the old ghost */
    cx = cx + dx; cy = cy + dy;
    if (cx > 30000) { cx = 2; }               /* wrapped negative (unsigned) */
    if (cx < 2) { cx = 2; }
    if (cx > 477) { cx = 477; }
    if (cy > 30000) { cy = 2; }
    if (cy < 2) { cy = 2; }
    if (cy > 242) { cy = 242; }
    if (armed && tool != 3) { ghost(); }      /* draw the new one */
    cross();                                  /* redraw */
    return 0;
}

int jumpcur(int nx, int ny) {                 /* mouse: absolute move */
    cross();
    if (armed && tool != 3) { ghost(); }
    cx = nx; cy = ny;
    if (cx < 2) { cx = 2; }
    if (cx > 477) { cx = 477; }
    if (cy < 2) { cy = 2; }
    if (cy > 242) { cy = 242; }
    if (armed && tool != 3) { ghost(); }
    cross();
    return 0;
}

/* mouse actions, fed by lib_ptr events ------------------------------------- */
int at_palette(int x, int y) {
    int i;
    if (y < 246) { return 0; }
    i = 0;
    while (i < 8) {
        if (x >= swx(i) && x <= swx(i) + 20) { pick_col(i); }
        i = i + 1;
    }
    i = 0;
    while (i < 4) {
        if (x >= tcx(i) && x <= tcx(i) + 24) { pick_tool(i); }
        i = i + 1;
    }
    return 1;
}

int m_press(int x, int y) {
    if (at_palette(x, y)) { return 0; }
    jumpcur(x, y);
    cross();
    if (tool == 3) { drop(); }
    else { ax = cx; ay = cy; armed = 1; ghost(); mdown = 1; }
    cross();
    status();
    return 0;
}

int m_release(int x, int y) {
    if (mdown == 0) { return 0; }
    jumpcur(x, y);
    cross();
    ghost(); commit(); armed = 0; mdown = 0;
    cross();
    status();
    return 0;
}

int main() {
    int k; int step;
    if (peek(GLID) != 71) { puts("?No display"); return 1; }
    pal[0] = 65535;  pal[1] = 63488; pal[2] = 2016;  pal[3] = 31;
    pal[4] = 65504;  pal[5] = 2047;  pal[6] = 63519; pal[7] = 64512;
    nsh = 0; tool = 0; col = 0; armed = 0; mdown = 0;
    cx = 240; cy = 120;

    vp_all();
    fillm(1); pen(0);                            /* clear the whole screen */
    mov(0, 0); gput(52); gw(479); gw(271);
    fillm(0);
    palette();                                   /* leaves the canvas viewport */
    outs("PAINT - wasd/WASD/arrows move, l b c f tools, 1-8 colours,");
    outc(13); outc(10);
    outs("SPACE anchor/commit, x cancel, e erase last, n new, q quit");
    outc(13); outc(10);
    outs("mouse: press-drag-release draws; click the palette to select");
    outc(13); outc(10);
    ptr_init();
    status();
    cross();

    k = 1;                                       /* running flag */
    while (k) {
        step = ptr_ev();
        if (step == 1) { m_press(ptr_x, ptr_y); }
        else if (step == 2) { if (mdown) { jumpcur(ptr_x, ptr_y); } }
        else if (step == 3) { m_release(ptr_x, ptr_y); }
        else if (step == 4) {
            if (armed) { cross(); ghost(); cross(); armed = 0; mdown = 0; status(); }
        }
        else if (ptr_key == 'q') { k = 0; }
        else {
            k = ptr_key;
            if (k == 128) { mvcur(0, 4); }           /* arrows */
            if (k == 129) { mvcur(0, 0 - 4); }
            if (k == 130) { mvcur(4, 0); }
            if (k == 131) { mvcur(0 - 4, 0); }
            if (k == 'w') { mvcur(0, 1); }           /* window y is UP */
            if (k == 's') { mvcur(0, 0 - 1); }
            if (k == 'a') { mvcur(0 - 1, 0); }
            if (k == 'd') { mvcur(1, 0); }
            if (k == 'W') { mvcur(0, 8); }
            if (k == 'S') { mvcur(0, 0 - 8); }
            if (k == 'A') { mvcur(0 - 8, 0); }
            if (k == 'D') { mvcur(8, 0); }
            if (k >= '1' && k <= '8') { pick_col(k - '1'); }
            if (k == 'l') { pick_tool(0); }
            if (k == 'b') { pick_tool(1); }
            if (k == 'c') { pick_tool(2); }
            if (k == 'f') { pick_tool(3); }
            if (k == 32) {
                cross();
                if (tool == 3) { drop(); }
                else if (armed) { ghost(); commit(); armed = 0; }
                else { ax = cx; ay = cy; armed = 1; ghost(); }
                cross();
                status();
            }
            if (k == 'x' && armed) { cross(); ghost(); cross(); armed = 0; status(); }
            if ((k == 'e' || k == 'u') && nsh > 0) {
                cross();
                if (armed) { ghost(); armed = 0; }
                nsh = nsh - 1; replay(); cross(); status();
            }
            if (k == 'n') {
                cross();
                if (armed) { ghost(); armed = 0; }
                nsh = 0; replay(); cross(); status();
            }
            k = 1;                               /* keep running */
        }
    }
    cross();                                     /* leave a clean screen */
    if (armed) { ghost(); }
    ptr_done();
    gwait();
    outc(13); outc(10); puts("bye");
    return 0;
}
