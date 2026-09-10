/* term.c -- the Term app: an on-screen console in the full-screen app frame
 * (two-mode P5). It IS the glass TTY (the P2 on-screen console) presented as a
 * desktop app: type a command, it runs, its output appears on the GL screen.
 *
 *   term> ls
 *   term> cube
 *   term> exit          -> back to the Finder desktop
 *
 * There is no "run a program and return" syscall (SYS_EXEC/SYS_RUNSH both replace
 * the caller), so Term persists the way Finder auto-returns: after reading a
 * command it writes "/TERM.RUN" = "<cmd>\nrun /bin/term.bin -c" and hands it to
 * the shell (SYS_RUNSH). The command runs (its stdout mirrors to the glass
 * console), then Term RE-launches in CONTINUE mode (-c: keep the screen, don't
 * re-clear), so the session accumulates on screen. `exit` (or a blank line then
 * ESC) becomes Finder instead. Launched from Finder's APPS menu ('a', then T).
 */

//#use abi     /* GCLS BIOS, SYS_RUNSH/SYS_EXEC, FRESOLVE/FWOPEN..., argstr, CONOUT */
//#use ptr     /* rawkey / outc / outs */

//#define GFXPRES 0x60A4  /* 1 = GL card fitted */
//#define GTSUSP  0x60A7  /* 1 = a full-screen GL app owns the screen (console off) */
//#define GCONEN  0x60AF  /* 1 = glass TTY console enabled */
//#define GCLS    0x014E  /* BIOS: clear the glass TTY + home */

char cmd[64];

int streq(char *a, char *b) {
    int i; i = 0;
    while (a[i] != 0 && b[i] != 0) { if (a[i] != b[i]) { return 0; } i = i + 1; }
    return a[i] == b[i];
}

/* read a line into cmd[], echoing to the console; returns the length */
int getln() {
    int n; int k; int done;
    n = 0; done = 0;
    while (done == 0) {
        k = rawkey();
        if (k == 13 || k == 10) { done = 1; }
        else if (k == 8 || k == 127) { if (n > 0) { n = n - 1; outc(8); outc(32); outc(8); } }
        else if (k >= 32 && k < 127) { if (n < 62) { cmd[n] = k; n = n + 1; outc(k); } }
    }
    cmd[n] = 0;
    outc(13); outc(10);
    return n;
}

int putstr(char *s) { int i; i = 0; while (s[i]) { bios(FPUTB, 0, s[i]); i = i + 1; } return 0; }

/* /TERM.RUN = "<cmd>\nrun /bin/term.bin -c\n": run the command, then re-launch
 * Term in continue mode (keep the screen). */
int write_run() {
    bios(FRESOLVE, "/TERM.RUN", 0);
    bios(FDELETE, "/TERM.RUN", 0);
    bios(FRESOLVE, "/TERM.RUN", 0);
    bios(FWOPEN, 0, 0);
    putstr(cmd); bios(FPUTB, 0, 10);
    putstr("run /bin/term.bin -c"); bios(FPUTB, 0, 10);
    bios(FCLOSE, 0, 0);
    return 0;
}

int main() {
    char *a; int cont; int n;
    if (peek(GFXPRES) == 0) { puts("?No display"); return 1; }
    poke(GTSUSP, 0);                               /* the console owns the screen */
    poke(GCONEN, 1);                               /* enable the on-screen console */
    a = argstr();
    while (*a == 32) { a = a + 1; }
    cont = (*a == '-' && *(a + 1) == 'c');
    if (cont == 0) {                               /* first launch: fresh screen + banner */
        bios(GCLS, 0, 0);
        outs("P8X TERM -- run commands on screen; type exit to leave\r\n");
    }
    outs("term> ");
    n = getln();
    if (streq(cmd, "exit") || streq(cmd, "quit")) {
        poke(GCONEN, 0);                           /* console off; back to the desktop */
        bios(SYS_EXEC, "/bin/finder.bin", 0);      /* become Finder (no return) */
        return 0;                                  /* only if that failed */
    }
    write_run();                                   /* run the command, then re-launch us */
    bios(SYS_RUNSH, "/TERM.RUN", 0);               /* no return */
    return 0;
}
