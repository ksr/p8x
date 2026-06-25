/* dump.c — hex + ASCII dump of 256 bytes of memory (the OS `DUMP` command).
 *
 *     DUMP B000            16 rows of 16 bytes from $B000, hex then ASCII
 *
 * Reads memory with peek(); the address argument is hex (no `$`/`0x` needed).
 * Prints one 256-byte block and exits — run again with a new address for more
 * (the old built-in paged with CR; this is a plain one-shot dump).
 */
int hexval(int c) {                          /* hex digit -> 0..15, or 16 if not hex */
    if (c >= 48 && c <= 57) { return c - 48; }
    if (c >= 65 && c <= 70) { return c - 55; }   /* A-F */
    if (c >= 97 && c <= 102) { return c - 87; }  /* a-f */
    return 16;
}
int hd(int v) {                              /* 0..15 -> hex digit char */
    if (v < 10) { return 48 + v; }
    return 55 + v;                           /* 10 -> 'A' */
}
int ph2(int b) {                             /* print a byte as two hex digits */
    putchar(hd((b / 16) & 15));
    putchar(hd(b & 15));
    return 0;
}

int main() {
    char *a;
    int addr;
    int v;
    int row;
    int col;
    int base;
    int c;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        puts("usage: DUMP hexaddr   256 bytes (hex + ASCII) from hexaddr");
        return 0;
    }
    addr = 0;                                /* parse the hex address */
    v = hexval(*a);
    while (v < 16) {
        addr = addr * 16 + v;
        a = a + 1;
        v = hexval(*a);
    }

    row = 0;
    while (row < 16) {
        base = addr + row * 16;
        ph2((base / 256) & 255);             /* address, 4 hex */
        ph2(base & 255);
        putchar(58); putchar(32);            /* ": " */
        col = 0;
        while (col < 16) {                   /* 16 hex bytes */
            ph2(peek(base + col) & 255);
            putchar(32);
            col = col + 1;
        }
        putchar(124);                        /* '|' */
        col = 0;
        while (col < 16) {                   /* ASCII gutter */
            c = peek(base + col) & 255;
            if (c >= 32 && c <= 126) { putchar(c); } else { putchar('.'); }
            col = col + 1;
        }
        putchar(124);                        /* '|' */
        putchar(10);
        row = row + 1;
    }
    return 0;
}
