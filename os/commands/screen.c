/* screen.c -- turn the on-screen text console (the "glass TTY") on or off.
 *
 * Two-mode P2 (docs/p8x-two-mode-design.md): when a GL card is fitted, the BIOS
 * CONOUT can MIRROR every console byte onto the GL screen as well as the serial
 * ACIA, so the OS and every program appear on the display. That mirror is OPT-IN
 * and OFF by default (GCONEN=0) -- the graphics ecosystem (cube, paint, BASIC,
 * the WM, and the byte-exact GL tests) shares that one screen, so the console is
 * only drawn on it when you ask.
 *
 *     screen on    enable  -- clear the screen + start mirroring CONOUT to it
 *     screen off   disable -- back to serial-only console
 *     screen       (report the current state)
 *
 * `on` also calls GCLS (clear the screen + home the text cursor). A full-screen
 * GL program still suspends the console while it draws (GTSUSP); quitting back to
 * the shell resumes it. Requires a display: with no card this is a no-op + note.
 */

//#use abi     /* argstr, and the console flag address */

//#define GFXPRES 0x60A4  /* 1 = GL card fitted */
//#define GCONEN  0x60AF  /* 1 = glass TTY console enabled */
//#define GCLS    0x014E  /* BIOS: clear the glass TTY + home the cursor */

int main() {
    char *a;
    a = argstr();
    while (*a == 32) { a = a + 1; }

    if (*a == 'o' && *(a + 1) == 'n') {              /* "on" */
        if (peek(GFXPRES) == 0) { puts("screen: no display fitted"); return 1; }
        poke(GCONEN, 1);
        bios(GCLS, 0, 0);                            /* clear + home the console */
        puts("screen: console on");
        return 0;
    }
    if (*a == 'o' && *(a + 1) == 'f') {              /* "off" */
        poke(GCONEN, 0);
        puts("screen: console off");
        return 0;
    }
    if (*a == 0 || *a == 13) {                       /* report */
        if (peek(GCONEN)) { puts("screen: console on"); }
        else { puts("screen: console off"); }
        return 0;
    }
    puts("usage: screen on|off");
    return 1;
}
