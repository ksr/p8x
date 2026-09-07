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
 * -r  RESUME: the windows are already in the kernel (a launched app is
 *     coming back), so skip init/open -- just redraw and re-enter the loop.
 *
 * Boot is unchanged -- monitor, B, shell -- this is opt-in by command. The
 * full standalone `desk` (its own in-TPA WM) is unaffected; this is the
 * kernel-backed successor, grown a rung at a time (docs/p8x-wm-design.md).
 */

//#use abi

//#define GLDATA 0xFF50
//#define GLSTAT 0xFF51
//#define GLID   0xFF54

char param[22];

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

/* the menu bar: a white strip across the top 14 rows with black text. Drawn
 * AFTER every kernel repaint (the repaint's FLOOD covers these rows too). */
int menubar() {
    gp(224); gp(1);                           /* PRMFIL 1 (filled)     */
    gp(6); gp(31); gp(63); gp(31);            /* COLOR white           */
    gp(16); gw(0); gw(258);                   /* MOVE 0,258            */
    gp(52); gw(479); gw(271);                 /* RECT: the bar         */
    gp(224); gp(0);                           /* PRMFIL 0              */
    gp(6); gp(0); gp(0); gp(0);               /* COLOR black           */
    wtext(8, 261, "DESK   L=PAINT   C=CLOSE   Q=QUIT");
    return 0;
}

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
    char *ap; int k; int going;
    if (peek(GLID) != 71) { puts("?No display"); return 1; }
    ap = argstr();
    while (*ap == 32) { ap = ap + 1; }

    scene();                                  /* card list 30, always */
    if (ap[0] != '-' || ap[1] != 'r') {       /* fresh (not a resume) */
        bios(SYS_WKINIT, 0, 0);
        setw(40, 40, 210, 150, 30, "SHAPES"); /* content = card list 30 */
        setw(190, 90, 240, 130, 0, "NOTES");  /* both sit below the bar */
    }
    bios(SYS_WKREPAINT, 0, 0);
    menubar();
    puts("WDESK (man wdesk)");

    going = 1;
    while (going) {
        k = bios(SYS_WKEVENT, 0, 0);          /* one event */
        if (k & 256) { going = 0; }           /* carry -> quit (^D) */
        else if (k == 0) { menubar(); }       /* kernel repainted -> redraw bar */
        else if (k == 108 || k == 76) {       /* L: launch paint OVER wdesk */
            bios(SYS_EXEC, "/bin/paint.bin -w", 0);   /* never returns on ok */
            menubar();                        /* only reached if exec failed */
        }
        else if (k == 99 || k == 67) {        /* C: close the top window */
            bios(SYS_WKCLOSE, 0, 0);
            bios(SYS_WKREPAINT, 0, 0);
            menubar();
        }
        else if (k == 113 || k == 81) { going = 0; }  /* Q: quit */
    }

    gp(116); gp(30);                          /* CLDEL 30: tidy the card */
    while (peek(GLSTAT) & 64) { }
    puts("bye");
    return 0;
}
