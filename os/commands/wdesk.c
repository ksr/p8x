/* wdesk.c -- the desktop on the RESIDENT window-manager kernel.
 *
 * A thin launcher, the way the design doc always meant `desk` to end up:
 * the window manager lives in the OS (os/wmkernel_body.asm, folded into
 * p8xos.asm, syscalls SYS_WKINIT..SYS_WKPATH), so this program only
 * DESCRIBES the desktop and hands over. It records the SHAPES scene into
 * a card-resident command list, opens windows through SYS_WKOPEN, points
 * the kernel's launch key at paint, and calls SYS_WKRUN -- the resident
 * event loop (arrows move the top window, the mouse drags it, 'l'
 * launches, Ctrl-D leaves for the shell).
 *
 * THE PAYOFF: press 'l' and the kernel SYS_EXECs paint OVER this program
 * (the TPA holds one program; wdesk is gone). Quit paint and it calls
 * SYS_WKRUN itself (it was launched with -w), and the desktop comes back
 * with every window intact -- the records live in the OS and the picture
 * lives on the card, so nothing was lost when wdesk was replaced. That is
 * exactly what `desk` cannot do: launching an app destroys it.
 *
 * The full-featured standalone `desk` (menus, close boxes, FILES, TERM,
 * VIEW) stays as it is; those features migrate into the kernel in later
 * rungs. Boot is unchanged -- monitor, B, shell -- this is opt-in.
 */

//#use abi

//#define GLDATA 0xFF50
//#define GLSTAT 0xFF51
//#define GLID   0xFF54

char param[22];

int gp(int v) { while (peek(GLSTAT) & 128) { } poke(GLDATA, v); return 0; }
int gw(int v) { gp(v & 255); gp((v / 256) & 255); return 0; }

/* one 22-byte window record -> SYS_WKOPEN:
 *   x,y,w,h (little-endian pairs), content list id, title length, title(12) */
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

int main() {
    if (peek(GLID) != 71) { puts("?No display"); return 1; }

    /* SHAPES' scene -> card list 30, in window-LOCAL coordinates: a red
     * frame, and a filled yellow box that overruns the edge on purpose --
     * the card's per-window clip keeps it inside (see man desk). The list
     * stays on the card, so the kernel replays it with two wire bytes
     * (CLRUN 30) on every repaint, including the one after paint quits. */
    gp(112); gp(30);                          /* CLBEG 30                */
    gp(224); gp(0);                           /* PRMFIL 0 (outline)      */
    gp(6); gp(31); gp(0); gp(0);              /* COLOR red               */
    gp(16); gw(10); gw(10);                   /* MOVE 10,10              */
    gp(52); gw(198); gw(125);                 /* RECT to 198,125         */
    gp(224); gp(1);                           /* PRMFIL 1 (filled)       */
    gp(6); gp(31); gp(63); gp(0);             /* COLOR yellow            */
    gp(16); gw(150); gw(90);                  /* MOVE 150,90             */
    gp(52); gw(260); gw(180);                 /* RECT overrun -> clipped */
    gp(224); gp(0);
    gp(113);                                  /* CLEND                   */

    bios(SYS_WKINIT, 0, 0);
    setw(40, 40, 210, 150, 30, "SHAPES");     /* content = card list 30  */
    setw(190, 90, 240, 140, 0, "L: PAINT");   /* an empty reminder pane  */
    bios(SYS_WKPATH, "/bin/paint.bin -w", 0); /* the 'l' key launches paint;
                                                 -w: it resumes us on quit */
    puts("WDESK (man wdesk)");
    bios(SYS_WKRUN, 0, 0);                    /* the resident loop; ^D returns */

    gp(116); gp(30);                          /* CLDEL 30: tidy the card */
    while (peek(GLSTAT) & 64) { }
    puts("bye");
    return 0;
}
