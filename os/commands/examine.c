/* examine.c — interactively examine and modify memory: EXAMINE addr
 *
 *     EXAMINE 6A00     show  6A00: vv  then read a key:
 *                        Enter        keep the byte, advance to the next
 *                        two hex digits  write that byte, then advance
 *                        .            quit to the shell
 *
 * The interactive counterpart to DUMP (a read-only block view) and DEP (a blind
 * write). Mirrors the ROM monitor's `E` command. addr is hexadecimal; writes go
 * anywhere in the 64 K space via poke(). It needs only raw memory access and a
 * console key, so it lives in /bin, not the resident kernel.
 */
//#use abi     /* named BIOS/OS addresses (this command uses only the builtins) */
//#use err     /* eputs(): errors -> console, never into a redirect/pipe */

char *HD = "0123456789ABCDEF";

/* ph2/ph4: print a byte / a 16-bit word as hex digits. */
int ph2(int v) { putchar(HD[(v >> 4) & 15]); putchar(HD[v & 15]); return 0; }
int ph4(int v) { ph2((v >> 8) & 255); ph2(v & 255); return 0; }

/* hx: value of one hex digit (0..15), or 99 if not a hex digit. */
int hx(int c) {
    if (c >= '0' && c <= '9') { return c - '0'; }
    if (c >= 'A' && c <= 'F') { return c - 'A' + 10; }
    if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
    return 99;                              /* p8cc compares UNSIGNED: use an
                                             * out-of-range sentinel, not -1 */
}

/* nl: emit a CRLF line terminator (the P8X console expects CR then LF). */
int nl() { putchar(13); putchar(10); return 0; }

/* main: parse the hex address from the command line, then loop showing one
 * byte at a time and acting on each keystroke (Enter=advance, two hex
 * digits=write via poke() then advance, '.'=quit). Uses builtins peek/poke
 * for raw 64 K memory access and getchar/putchar for the console; no BIOS/OS
 * calls, so nothing here clobbers P1/P2 across the ABI. */
int main() {
    char *a;
    int addr;
    int d;
    int any;
    int c;
    int hi;
    int lo;

    a = argstr();                            /* raw argument tail after the command name */
    while (*a == 32) { a = a + 1; }          /* skip leading spaces (32 = ' ') */
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: EXAMINE addr   view/modify memory (Enter=next, 2 hex=write, .=quit)");
        return 0;
    }

    addr = 0;                                /* parse the hex address */
    any = 0;
    d = hx(*a);
    while (d < 16) {
        addr = addr * 16 + d;
        a = a + 1;
        any = 1;
        d = hx(*a);
    }
    if (any == 0) { eputs("examine: bad address"); return 1; }

    /* getchar() (SYS_GETC) echoes the key itself; on Enter it echoes CRLF and
     * queues an LF that the next getchar() returns -- so we echo nothing here,
     * and swallow that queued LF after an Enter. */
    while (1) {
        ph4(addr);                           /* "aaaa: vv " */
        putchar(':');
        putchar(32);
        ph2(peek(addr) & 255);
        putchar(32);
        c = getchar();
        if (c == -1) { return 0; }                     /* EOF -> quit */
        if (c == '.') { nl(); return 0; }              /* '.' -> quit */
        if (c == 13) { getchar(); addr = addr + 1; }   /* Enter: eat LF, advance */
        else {
            hi = hx(c);
            if (hi >= 16) { nl(); }                    /* bad digit -> stay here */
            else {
                c = getchar();                         /* second hex digit */
                lo = hx(c);
                if (lo >= 16) { nl(); }
                else {
                    poke(addr, (hi * 16 + lo) & 255);
                    nl();
                    addr = addr + 1;
                }
            }
        }
    }
    return 0;
}
