/* page.c -- the framebuffer pages, from the shell (stage 9c).
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
 * the next. A flip waits for the panel's frame boundary (tear-free). */
char path[2];

//#use gfx
//#use g3d

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
    if (g3probe() == 0) { puts("?No engine"); return 1; }
    f = 0;
    if (*ap == 'f' || *ap == 'F') { f = 1; }
    if (f) { g3flip(); }
    else { g3sync(); }
    return 0;
}
