/* page.c -- the framebuffer pages, from the shell (stage 9c; GL since 10b).
 *
 *     PAGE          rejoin: draw page = display page (PGSYNC)
 *     PAGE SYNC     the same, spelled out
 *     PAGE FLIP     flip: show what was just drawn, draw on the other page
 *
 * The display has two framebuffer pages (stage 8b). The shell tools all
 * render single-buffered, but a program that dies mid-flip can leave the
 * pages SPLIT -- drawing lands on the hidden page and the screen seems
 * frozen. `page` is the recovery: it rejoins them instantly. `page flip`
 * is the front door to manual double-buffering: draw a frame, flip, draw
 * the next. A flip waits for the panel's frame boundary (tear-free).
 *
 * Since stage 10b the page verbs are GRAPHICS-LANGUAGE opcodes (FLIP=2,
 * PGSYNC=3 -- see man gl / STAGE10-DESIGN.md) poked at the GL command
 * FIFO; the stage-9 record engine that used to carry them is retired. */
char path[2];

//#use gfx

//#define GLID   0xFF54  /* GL presence probe: 'G' when fitted           */
//#define GLDATA 0xFF50  /* the command FIFO: one opcode byte per verb   */
//#define GLSTAT 0xFF51  /* bit6 = busy (a flip holds it to the frame)   */

char *ap;

int main() {
    int f;
    ap = argstr();
    while (*ap == 32) { ap = ap + 1; }
    if (*ap == '-' && (*(ap + 1) == 'h' || *(ap + 1) == 'H')) {
        puts("usage: PAGE [sync|flip]   rejoin the framebuffer pages, or flip");
        return 0;
    }
    if (gpresent() == 0) { puts("?No display"); return 1; }
    if (peek(GLID) != 71) { puts("?No GL engine"); return 1; }
    f = 0;
    if (*ap == 'f' || *ap == 'F') { f = 1; }
    if (f) { poke(GLDATA, 2); }
    else { poke(GLDATA, 3); }
    while (peek(GLSTAT) & 64) { }      /* a flip waits for the frame tick */
    return 0;
}
