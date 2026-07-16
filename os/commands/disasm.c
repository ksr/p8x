/* disasm.c — disassemble a memory range: DISASM start end   (hex addresses).
 *
 *     disasm 7A00 7A20     show the instructions in [7A00, 7A20)
 *
 * Reads raw memory with peek() and decodes each byte via the opcode table
 * dt_op[]/dt_sh[]/dt_mn[] (generated from the same genucode.OPC the assembler
 * and microcode use — spliced with //#use distab, so disasm never drifts from
 * the ISA). Both addresses are hex; the range is half-open [start, end). Each
 * line is:  AAAA: bb bb ..   MNEMONIC operand.  An unknown byte prints "???"
 * and advances one byte. No screen/file access beyond peek + putchar, so it
 * redirects and pipes like any filter.  A loadable /BIN/DISASM.BIN program.
 *
 * Operand shapes (dt_sh): 0 none, 1 #imm8, 2 addr16, 3..8 (Pn)/(Pn)+, 9 a,a
 * (MOVW dst,src). Instruction length follows from the shape (1/2/3/5 bytes).
 *
 * Within the native p8cc.c subset (no ++/--, decls at top).
 */
//#use distab   /* dt_n, dt_op[], dt_sh[], dt_mn[] — the generated opcode table */
//#use err      /* eputs(): errors -> console, never into a redirect/pipe */

char *HD = "0123456789ABCDEF";

/* ph2/ph4: print a byte / a 16-bit word as hex digits (MSB first).
 * ph4 prints high byte then low byte, so a little-endian word reads normally. */
int ph2(int v) { putchar(HD[(v >> 4) & 15]); putchar(HD[v & 15]); return 0; }
int ph4(int v) { ph2((v >> 8) & 255); ph2(v & 255); return 0; }

/* hx: value of one hex digit (0..15), or 99 if not a hex digit (p8cc compares
 * UNSIGNED, so use an out-of-range sentinel, not -1). */
int hx(int c) {
    if (c >= '0' && c <= '9') { return c - '0'; }
    if (c >= 'A' && c <= 'F') { return c - 'A' + 10; }
    if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
    return 99;
}

/* prs: print a NUL-terminated string (no trailing newline). */
int prs(char *s) { while (*s != 0) { putchar(*s); s = s + 1; } return 0; }

/* ilen: instruction length in bytes for an operand shape. */
int ilen(int sh) {
    if (sh == 1) { return 2; }        /* opcode + imm8   */
    if (sh == 2) { return 3; }        /* opcode + addr16 */
    if (sh == 9) { return 5; }        /* opcode + a,a    */
    return 1;                         /* none / (Pn) / (Pn)+ */
}

/* w16: read a little-endian 16-bit word at addr. */
int w16(int addr) { return (peek(addr) & 255) | ((peek(addr + 1) & 255) << 8); }

/* preg: print the register-indirect operand for shapes 3..8, e.g. " (P2)+".
 * Shapes pair up: 3/4 -> P1, 5/6 -> P2, 7/8 -> P3, and the even member of each
 * pair (4,6,8) is the post-increment form (Pn)+. putchar(32) leads with a space
 * to match the leading space of the #imm/addr operand forms. */
int preg(int sh) {
    putchar(32); putchar('(');
    putchar('P');
    if (sh == 3 || sh == 4) { putchar('1'); }
    if (sh == 5 || sh == 6) { putchar('2'); }
    if (sh == 7 || sh == 8) { putchar('3'); }
    putchar(')');
    if (sh == 4 || sh == 6 || sh == 8) { putchar('+'); }
    return 0;
}

int main() {
    char *a;
    int start; int end; int addr;
    int d; int any;
    int op; int i; int found; int sh; int ln; int k;

    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (*a == 0 || *a == 13 ||
        (*a == '-' && (*(a + 1) == 'h' || *(a + 1) == 'H'))) {
        /* One usage message serves both "-h" (requested output) and "no args at
         * all"; it returns 0 either way, so it stays plain puts() on stdout and
         * `disasm -h >notes` still captures it. */
        puts("usage: disasm start end   disassemble hex range [start,end)");
        return 0;
    }
    start = 0; any = 0; d = hx(*a);          /* parse the start hex address */
    while (d < 16) { start = start * 16 + d; a = a + 1; any = 1; d = hx(*a); }
    /* Parse failures are errors, so they go to the console via eputs(): stdout
     * may be a redirect or a pipe, and `disasm zz >OUT` must not write the
     * diagnostic INTO OUT, nor feed it to a pipe stage as if it were listing. */
    if (any == 0) { eputs("disasm: bad start address"); return 1; }
    while (*a == 32) { a = a + 1; }
    end = 0; any = 0; d = hx(*a);            /* parse the end hex address */
    while (d < 16) { end = end * 16 + d; a = a + 1; any = 1; d = hx(*a); }
    if (any == 0) { eputs("disasm: need an end address"); return 1; }

    addr = start;
    while (addr < end) {
        op = peek(addr) & 255;
        /* Linear scan of the opcode table for this byte. found==99 is the
         * "not found" sentinel (99 is out of the valid 0..dt_n-1 index range);
         * setting i=dt_n breaks the loop early (the subset has no break). */
        found = 99; i = 0;
        while (i < dt_n) {
            if (dt_op[i] == op) { found = i; i = dt_n; }
            else { i = i + 1; }
        }
        ph4(addr); putchar(':'); putchar(32);
        if (found == 99) {
            ph2(op); prs("            ???"); putchar(13); putchar(10);
            addr = addr + 1;
        } else {
            sh = dt_sh[found];
            ln = ilen(sh);
            k = 0;                        /* raw bytes */
            while (k < ln) { ph2(peek(addr + k) & 255); putchar(32); k = k + 1; }
            /* Pad the raw-byte column to a fixed width so mnemonics align:
             * each byte above printed 3 chars ("bb "), so emit 3 spaces per
             * missing byte up to the max shape length of 5 (the a,a form). */
            k = ln;
            while (k < 5) { putchar(32); putchar(32); putchar(32); k = k + 1; }
            putchar(32);
            prs(dt_mn[found]);
            if (sh == 1) { prs(" #$"); ph2(peek(addr + 1) & 255); }
            if (sh == 2) { prs(" $"); ph4(w16(addr + 1)); }
            if (sh >= 3 && sh <= 8) { preg(sh); }
            if (sh == 9) { prs(" $"); ph4(w16(addr + 1)); prs(",$"); ph4(w16(addr + 3)); }
            putchar(13); putchar(10);
            addr = addr + ln;
        }
    }
    return 0;
}
