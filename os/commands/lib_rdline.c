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
/* readline(buf): fill buf with the next input line, LF-terminated on input.
 *   in:   buf — caller's char buffer, must hold at least 256 bytes (255 + NUL).
 *   out:  buf gets the line's bytes (CR stripped) followed by a NUL.
 *   ret:  1 if a line was read, 0 if input was already at EOF.
 * nextc() returns the next byte, or 65535 as its EOF sentinel (a p8cc int is
 * 16-bit, so a real byte 0..255 can never collide with 65535). The leading
 * check returns 0 only when the very first read is EOF; a partial final line
 * with no trailing LF still returns 1. CR (13) is dropped so CRLF sources land
 * the same as bare-LF ones; bytes past 255 are discarded but still consumed so
 * the stream stays aligned to the next LF. LF (10) ends the line, unstored. */
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
