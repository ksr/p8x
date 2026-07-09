/* dep.c — deposit hex byte values into memory: DEP addr b b b ...
 *
 *     DEP 8000 A9 01 60      store $A9,$01,$60 starting at $8000
 *     DEP 7A00 FF            store one byte
 *
 * The counterpart to DUMP. addr and each byte are hexadecimal; the low byte of
 * each parsed value is stored (via poke). No byte values is a no-op. Formerly an
 * OS built-in; now a /bin program -- it needs only raw memory access, which the
 * poke() runtime builtin provides, so it does not belong in the resident kernel.
 *
 * With great power: DEP writes anywhere in the 64 K space, including over the OS
 * or over this program itself -- exactly like the old built-in. Quiet on success
 * (Unix-style); prints a usage line for -h or a missing address.
 */

/* hx: value of one hex digit (0..15), or 99 if not a hex digit. */
int hx(int c) {
    if (c >= '0' && c <= '9') { return c - '0'; }
    if (c >= 'A' && c <= 'F') { return c - 'A' + 10; }
    if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
    return 99;                              /* p8cc compares UNSIGNED: use an
                                             * out-of-range sentinel, not -1 */
}

int main() {
    char *a;
    int addr;
    int v;
    int d;
    int any;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: DEP addr b b ...   store hex bytes at hex address addr");
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
    if (any == 0) { puts("dep: bad address"); return 1; }

    while (1) {                              /* each following hex byte value */
        while (*a == 32) { a = a + 1; }
        if (*a == 0 || *a == 13) { return 0; }
        v = 0;
        any = 0;
        d = hx(*a);
        while (d < 16) {
            v = v * 16 + d;
            a = a + 1;
            any = 1;
            d = hx(*a);
        }
        if (any == 0) { return 0; }          /* non-hex tail -> stop */
        poke(addr, v & 255);
        addr = addr + 1;
    }
    return 0;
}
