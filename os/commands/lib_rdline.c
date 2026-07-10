/* lib_rdline.c — read one line from the current input into a buffer.
 * (Named lib_rdline.c so it fits P8XFS's 12-char filename field; it defines the
 *  readline() helper — the `//#use rdline` token names the FILE, not the function.)
 *
 * Spliced in by `//#use rdline` (see README "Shared code").
 *   readline(buf):  read up to the next LF into buf (CR dropped, capped at 255,
 *                   NUL-terminated); returns 1 if a line was read, 0 at EOF.
 *
 * DEPENDS on lib_stdin's nextc(): a command that `//#use rdline` must also
 * `//#use stdin` ABOVE it (clib.py splices in directive order, so nextc() is
 * defined before this caller). Within the native p8cc.c subset.
 */
int readline(char *buf) {
    int n;
    int c;
    n = 0;
    c = nextc();
    if (c == 65535) { return 0; }
    while (c != 65535 && c != 10) {
        if (c != 13 && n < 255) { buf[n] = c; n = n + 1; }
        c = nextc();
    }
    buf[n] = 0;
    return 1;
}
