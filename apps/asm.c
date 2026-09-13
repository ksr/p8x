/* asm.c - the P8X native two-pass assembler written in C (2026-09-13), the
 * size/speed twin of apps/p8xasm.asm. Same syntax, error messages and output:
 * every test that locks the asm one to the host assembler byte for byte
 * (coverage, self-host, .include, ;#use) runs against this build too.
 *
 *     RUN /binc/asm.bin SRC.ASM OUT.BIN
 *
 * Build: cat apps/opctab.c apps/asm.c > asmc.c  (the opcode table, generated
 *        by generators/gen_p8xopc.py)  ->  clib.py -> p8cc.py
 * Layout: the C image (about 14 KB) ends below $A800; the hashed symbol table
 * lives at $A800-$C5FF (16-byte entries: name[12] value[2] next[2], 480
 * symbols -- the asm build parks its table right after its 4 KB of code, at
 * $8000, and holds 1,120), the 256 chain heads at $C600, the source sector at
 * $C900, the include sector at $CC00, the BIOS directory-scan page at $CE00
 * and the path buffers at $D000: the asm build's map above the image.
 *
 * Subset notes: no break/continue, int compares unsigned, no longjmp -- an
 * error prints its message + the line and sets `err`; the pass loop stops.
 */
//#use abi
//#define FFIND    0x0118
//#define FNAME    0x604A
//#define DIRLBA   0x6073
//#define DIRN     0x6074
//#define DIRLBA1  0x6080
//#define SYMTAB   0xA800
//#define SYMEND   0xC600
//#define HEADS    0xC600
//#define SECBUF   0xC900
//#define INCBUF   0xCC00
//#define DIRPAGE  0xCE
//#define SRCPATH  0xD000
//#define OUTPATH  0xD030
//#define ARGTMP   0xD060
//#define INCPATH  0xD090
//#define UPATH    0xD110
//#define USELIST  0xD140

char linebuf[128];          /* the current source line */
char nambuf[16];            /* the identifier as written (12 kept) */
char mnbuf[16];             /* the same, upcased */
char srcfn[12];             /* the source's FNAME + dir context (re-opened each pass) */
char outfn[12];             /* the output's leaf + dir context (for FCLOSE) */
int srcdir0; int srcdir1; int srcdir2;
int outdir0; int outdir1; int outdir2;
int letidx[26];             /* first OPCTAB record per initial letter */
char *tp;                   /* the line cursor */
int pc;
int orgbase;
int orgset;
int pass;
int val;                    /* expression result */
int cnt;                    /* term value */
int shape;
int opcb;
int symp;                   /* symbol-table append pointer */
char *op1p;                 /* operand cursors */
char *op2p;
char *dispp;
int hilo;
int err;
int leof;
int usecount;
int usedone;
int inchave;
int incdone;

int eval();
int asmerr(char *msg);

/* ---- output ---- */
int puts_(char *s) { bios(PUTS, s, 0); return 0; }
int emit(int b) {                          /* pass 2 writes, both passes count */
    if (pass) bios(FPUTB, 0, b);
    pc = pc + 1;
    return 0;
}

/* ---- errors: message, the offending line, and stop ---- */
int asmerr(char *msg) {
    char *p;
    if (err) return 0;
    err = 1;
    puts_(msg);
    p = linebuf;
    while (*p && *p != 13 && *p != 10) { bios(CONOUT, 0, *p); p = p + 1; }
    bios(CONOUT, 0, 13); bios(CONOUT, 0, 10);
    return 0;
}

/* ---- characters ---- */
int isdig(int c) { return c >= '0' && c <= '9'; }
int upcase(int c) { if (c >= 'a' && c <= 'z') return c - 32; return c; }
int isidch(int c) {
    if (c == '.' || c == '_') return 1;
    if (isdig(c)) return 1;
    c = upcase(c);
    return c >= 'A' && c <= 'Z';
}
int hexval(int c) {
    if (isdig(c)) return c - '0';
    c = upcase(c);
    if (c >= 'A' && c <= 'F') return c - 55;
    return -1;
}
int skipsp() { while (*tp == ' ' || *tp == 9) tp = tp + 1; return 0; }

/* ---- tokens ---- */
int readtok() {                            /* identifier at tp -> nambuf / mnbuf */
    int i; int c;
    i = 0;
    while (i < 16) { nambuf[i] = 0; mnbuf[i] = 0; i = i + 1; }
    i = 0; c = *tp;
    while ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '.') {
        if (i < 12) {
            nambuf[i] = c;
            if (c >= 'a' && c <= 'z') c = c - 32;
            mnbuf[i] = c; i = i + 1;
        }
        tp = tp + 1; c = *tp;
    }
    return 0;
}

/* ---- symbols: 256 chains through 16-byte entries at SYMTAB ---- */
int symhash() {                            /* -> the chain head's address */
    int h; int i; int c;
    h = 0; i = 0; c = nambuf[0];
    while (c) {                            /* h = 2h + c over the name */
        h = (h + h + (c & 255)) & 255;
        i = i + 1; c = nambuf[i];
    }
    return HEADS + h + h;
}
int symfind() {                            /* -> the entry, 0 if absent; cnt = value */
    int *hp; int e; char *p; int k; int m;
    hp = symhash(); e = *hp;
    while (e) {
        p = e; k = 0; m = 1;
        while (m && k < 12) { if (p[k] != nambuf[k]) m = 0; k = k + 1; }
        if (m) { hp = p + 12; cnt = *hp; return e; }
        hp = p + 14; e = *hp;
    }
    return 0;
}
int symdef() {                             /* define / update nambuf = val */
    int e; int *hp; int *w; char *p; int k;
    e = symfind();
    if (e) { w = e + 12; *w = val; return 0; }
    if (symp + 16 > SYMEND) { asmerr("?too many symbols: "); return 0; }
    p = symp; k = 0;
    while (k < 12) { p[k] = nambuf[k]; k = k + 1; }
    w = p + 12; *w = val;
    hp = symhash(); w = p + 14; *w = *hp; *hp = symp;
    symp = symp + 16;
    return 0;
}

/* ---- expressions: [<|>] term { (+|-) term }, term = $hex | dec | 'c' | symbol ---- */
int rdterm() {
    int c; int d;
    cnt = 0; c = *tp;
    if (c == '$') {
        tp = tp + 1; d = hexval(*tp);
        while (d != -1) { cnt = (cnt << 4) | d; tp = tp + 1; d = hexval(*tp); }
        return 0;
    }
    if (c == 39) {                         /* 'c' */
        tp = tp + 1; cnt = *tp & 255; tp = tp + 1;
        if (*tp == 39) tp = tp + 1;
        return 0;
    }
    if (isdig(c)) {
        while (isdig(*tp)) { cnt = cnt + cnt; cnt = cnt + (cnt << 2) + (*tp - '0'); tp = tp + 1; }
        return 0;
    }
    readtok();
    if (symfind()) return 0;
    cnt = 0;
    if (pass) asmerr("?undefined: ");
    return 0;
}
int eval() {
    int sign;
    hilo = 0;
    if (*tp == '<') { hilo = 1; tp = tp + 1; }
    else if (*tp == '>') { hilo = 2; tp = tp + 1; }
    val = 0; sign = 1;
    while (1) {
        rdterm(); if (err) return 0;
        if (sign) val = val + cnt; else val = val - cnt;
        if (*tp == '+') { sign = 1; tp = tp + 1; }
        else if (*tp == '-') { sign = 0; tp = tp + 1; }
        else {
            if (hilo == 1) val = val & 255;
            else if (hilo == 2) val = val >> 8;
            return 0;
        }
    }
}

/* ---- the opcode table: [shape][opcode][chars]0 ... 0xFF, sorted, letter-indexed ---- */
int opcindex() {
    int i; int last; int c;
    i = 0; last = 0;
    while (i < 26) { letidx[i] = -1; i = i + 1; }
    i = 0;
    while ((opctab[i] & 255) != 255) {
        c = opctab[i + 2];
        if (c != last) { letidx[c - 'A'] = i; last = c; }
        i = i + 2;
        while (opctab[i]) i = i + 1;
        i = i + 1;
    }
    return 0;
}
int opcfind() {                            /* (mnbuf, shape) -> 1 and opcb, else 0 */
    int i; int c; int k; int m;
    c = mnbuf[0] - 'A';
    if (c >= 26) return 0;
    i = letidx[c];
    if (i == -1) return 0;
    while ((opctab[i] & 255) != 255 && opctab[i + 2] == mnbuf[0]) {
        if (opctab[i] == shape) {
            k = 1; m = 1;
            while (m) {
                if (opctab[i + 2 + k] != mnbuf[k]) m = 0;
                else if (mnbuf[k] == 0) { opcb = opctab[i + 1] & 255; return 1; }
                else k = k + 1;
            }
        }
        i = i + 2;
        while (opctab[i]) i = i + 1;
        i = i + 1;
    }
    return 0;
}

/* ---- operand shapes (the OPCTAB's codes; imm8 vs imm16 by the host's lit8 rule) ---- */
int lit8() {                               /* is the immediate TEXT at tp byte-sized? */
    int c; int n;
    c = *tp;
    if (c == '<' || c == '>') return 1;
    if (c == 39) { if (tp[2] != 39) return 0; tp = tp + 3; }
    else if (c == '$' || (c == '0' && (tp[1] == 'x' || tp[1] == 'X'))) {
        if (c == '$') tp = tp + 1; else tp = tp + 2;
        n = 0;
        while (hexval(*tp) != -1) { n = n + 1; tp = tp + 1; }
        if (n == 0 || n > 2) return 0;
    } else if (isdig(c)) {
        rdterm();
        if (cnt > 255) return 0;
    } else return 0;
    skipsp();
    c = *tp;
    return c == 0 || c == 13 || c == 10 || c == ';';
}
int classop() {                            /* one operand -> shape */
    int c; int n;
    c = *tp;
    if (c == 0 || c == 13 || c == 10 || c == ';') return 0;
    if (c == '#') { tp = tp + 1; return 1; }
    if (c != '(') return 2;
    n = tp[2] - '0';
    if (tp[3] == '+') {                    /* (Pn+d) */
        tp = tp + 4; dispp = tp;
        while (*tp && *tp != ')') tp = tp + 1;
        if (*tp == 0) { asmerr("?syntax: "); return 0; }
        tp = tp + 1;
        return 12 + n;
    }
    if (tp[3] != ')') { asmerr("?syntax: "); return 0; }
    if (tp[4] == '+') { tp = tp + 5; return 4 + ((n - 1) << 1); }
    tp = tp + 4;
    return 3 + ((n - 1) << 1);
}
int parseop() {                            /* the operand field -> shape, op1p/op2p/dispp */
    int s1; int s2; int c;
    s1 = classop(); op1p = tp;
    if (err) return 0;
    c = *tp;
    while (c && c != 13 && c != 10 && c != ';' && c != ',') {
        if (c == 39) tp = tp + 2;          /* a 'c' literal may be ',' */
        tp = tp + 1; c = *tp;
    }
    if (c != ',') return s1;
    tp = tp + 1; skipsp();
    s2 = classop(); op2p = tp;
    if (err) return 0;
    if (s1 == 2) {
        if (s2 == 2) return 10;
        if (s2 == 1) { tp = op2p; if (lit8()) return 11; return 12; }
        if (s2 >= 13 && s2 <= 15) return s2 + 3;
    } else if (s1 >= 13 && s1 <= 15 && s2 == 2) return s1 + 6;
    asmerr("?syntax: ");
    return 0;
}

/* ---- emit the operand bytes for a shape ---- */
int emabs(char *p) { tp = p; eval(); emit(val & 255); emit(val >> 8); return 0; }
int emimm(char *p) { tp = p; eval(); emit(val & 255); return 0; }
int doinstr() {
    int s;
    if (mnbuf[0] == '.') return 0;          /* (directives are handled by the caller) */
    s = parseop(); if (err) return 0;
    shape = s;
    if (!opcfind()) {
        if (s != 1) { asmerr("?syntax: "); return 0; }
        shape = 9;                          /* a lone # with no imm8 form: LDPn #w */
        if (!opcfind()) { asmerr("?syntax: "); return 0; }
    }
    emit(opcb);
    s = shape;
    if (s == 1) return emimm(op1p);
    if (s == 2 || s == 9) return emabs(op1p);
    if (s == 10 || s == 12) { emabs(op1p); return emabs(op2p); }
    if (s == 11) { emabs(op1p); return emimm(op2p); }
    if (s >= 13 && s <= 15) return emimm(dispp);
    if (s >= 16 && s <= 18) { emabs(op1p); return emimm(dispp); }
    if (s >= 19 && s <= 21) { emabs(op2p); return emimm(dispp); }
    return 0;
}
int comma() {                              /* skip blanks; step over a ',' -> 1 */
    skipsp();
    if (*tp != ',') return 0;
    tp = tp + 1; skipsp();
    return 1;
}
int dodir() {
    int c; int n; int f;
    c = mnbuf[1];
    if (c == 'O') {
        eval(); if (err) return 0;
        if (pass == 0) { if (orgset == 0) { orgbase = val; orgset = 1; } pc = val; return 0; }
        if (val < pc) { asmerr("?backward .org: "); return 0; }
        while (pc < val) emit(0);
        return 0;
    }
    if (c == 'B') { n = 1; while (n) { eval(); if (err) return 0; emit(val & 255); n = comma(); } return 0; }
    if (c == 'W') { n = 1; while (n) { eval(); if (err) return 0; emit(val & 255); emit(val >> 8); n = comma(); } return 0; }
    if (c == 'F') {
        eval(); if (err) return 0;
        n = val; f = 0;
        if (comma()) { eval(); if (err) return 0; f = val & 255; }
        while (n) { emit(f); n = n - 1; }
        return 0;
    }
    if (c == 'A') {
        skipsp();
        if (*tp != '"') { asmerr("?syntax: "); return 0; }
        tp = tp + 1;
        while (*tp != '"') {
            if (*tp == 0) { asmerr("?syntax: "); return 0; }
            c = *tp & 255; tp = tp + 1;
            if (c == 92) {                       /* a backslash escape, as the host assembler decodes them */
                c = *tp & 255; if (c == 0) { asmerr("?syntax: "); return 0; }
                tp = tp + 1;
                if (c == 'n') c = 10; else if (c == 't') c = 9; else if (c == 'r') c = 13; else if (c == '0') c = 0;
            }
            emit(c);
        }
        tp = tp + 1;
        if (mnbuf[6] == 'Z') emit(0);
        return 0;
    }
    asmerr("?syntax: ");
    return 0;
}

/* ---- source input: lines over the BIOS read stream, includes appended ---- */
int strncpy_(char *d, char *s, int n) { while (n) { *d = *s; d = d + 1; s = s + 1; n = n - 1; } return 0; }
int savesrc() {
    strncpy_(srcfn, FNAME, 12);
    srcdir0 = peek(DIRLBA); srcdir1 = peek(DIRN); srcdir2 = peek(DIRLBA1);
    return 0;
}
int restsrc() {
    strncpy_(FNAME, srcfn, 12);
    poke(DIRLBA, srcdir0); poke(DIRN, srcdir1); poke(DIRLBA1, srcdir2);
    return 0;
}
int strcat_(char *d, char *s) { while (*d) d = d + 1; while (*s) { *d = *s; d = d + 1; s = s + 1; } *d = 0; return 0; }
int nextuse() {                            /* open the next unread include: 1 opened, 0 none */
    char *u;
    if (usedone < usecount) {
        u = UPATH;
        *u = 0; strcat_(u, "/lib/"); strcat_(u, USELIST + (usedone << 4)); strcat_(u, ".inc");
        usedone = usedone + 1;
    } else if (inchave && incdone == 0) {
        incdone = 1; u = INCPATH;
    } else return 0;
    if (bios(FRESOLVE, u, 0) & 256) { asmerr("?missing #use include: "); return 0; }
    if (bios(FOPEN, INCBUF, 0) & 256) { asmerr("?missing #use include: "); return 0; }
    return 1;
}
int srcget() {                             /* next byte, -1 at the end of everything */
    int c;
    while (1) {
        c = bios(FGETB, 0, 0);
        if ((c & 256) == 0) return c & 255;
        if (!nextuse()) return -1;
        if (err) return -1;
    }
}
int match(char *pat) {                     /* does tp start with pat? (tp advanced if so) */
    char *s;
    s = tp;
    while (*pat) { if (*s != *pat) return 0; s = s + 1; pat = pat + 1; }
    tp = s;
    return 1;
}
int chkuse() {                             /* ";#use NAME" -> record it: 1 */
    char *d; int c;
    tp = linebuf; skipsp();
    if (!match(";#use")) return 0;
    if (*tp != ' ' && *tp != 9) return 0;
    skipsp();
    if (*tp == 0 || *tp == 13) return 0;
    if (usecount < 4) {
        d = USELIST + (usecount << 4); c = *tp;
        while (c && c != ' ' && c != 13 && c != 9) { *d = c; d = d + 1; tp = tp + 1; c = *tp; }
        *d = 0;
        usecount = usecount + 1;
    }
    return 1;
}
int chkinc() {                             /* '.include "path"' -> INCPATH: 1 */
    char *d; char *s;
    if (inchave) return 0;
    tp = linebuf; skipsp();
    if (!match(".include")) return 0;
    skipsp();
    if (*tp != '"') return 0;
    tp = tp + 1;
    d = INCPATH;
    if (*tp != '/') {                      /* relative to the source's directory */
        s = SRCPATH;
        while (*s) { *d = *s; d = d + 1; s = s + 1; }
        while (d > INCPATH && d[-1] != '/') d = d - 1;
    }
    while (*tp && *tp != '"') { *d = *tp; d = d + 1; tp = tp + 1; }
    *d = 0;
    inchave = 1;
    return 1;
}
int nextline() {                           /* linebuf <- the next line; leof at the end */
    int n; int c; int again;
    again = 1;
    while (again) {
        n = 0; c = bios(FGETB, 0, 0);
        if (c & 256) c = srcget();
        while (c != -1 && c != 10) {
            if (c != 13 && n < 127) { linebuf[n] = c; n = n + 1; }
            c = bios(FGETB, 0, 0);
            if (c & 256) c = srcget();
        }
        if (c == -1 && n == 0) { leof = 1; return 0; }
        if (err) { leof = 1; return 0; }
        linebuf[n] = 0;
        again = chkuse();
        if (again == 0) again = chkinc();
    }
    return 0;
}

/* ---- a pass ---- */
int assemble() {
    int c;
    pc = orgbase;
    restsrc();
    usecount = 0; usedone = 0; inchave = 0; incdone = 0; leof = 0;
    bios(FOPEN, SECBUF, 0);
    while (1) {
        nextline();
        if (leof || err) return 0;
        tp = linebuf; skipsp();
        c = *tp;
        while (c && c != ';') {
            readtok(); skipsp();
            if (*tp == ':') {
                tp = tp + 1;
                if (pass == 0) { val = pc; symdef(); }
                skipsp(); c = *tp;
            } else if (*tp == '=') {
                tp = tp + 1; skipsp();
                eval(); if (err) return 0;
                symdef(); c = 0;
            } else {
                if (mnbuf[0] == '.') dodir(); else doinstr();
                c = 0;
            }
            if (err) return 0;
        }
    }
}

/* ---- arguments and paths ---- */
int abspath(char *dst, char *arg) {        /* CWD-prefix a relative path */
    char *d;
    d = dst;
    if (*arg == 0) { *d = 0; return 0; }
    if (*arg != '/') {
        bios(SYS_GETCWD, d, 0);
        while (*d) d = d + 1;
        if (d[-1] != '/') { *d = '/'; d = d + 1; }
    }
    while (*arg) { *d = *arg; d = d + 1; arg = arg + 1; }
    *d = 0;
    return 0;
}
char *argword(char *a, char *dst) {        /* copy one word of the argument tail */
    while (*a == ' ') a = a + 1;
    while (*a && *a != ' ' && *a != 13) { *dst = *a; dst = dst + 1; a = a + 1; }
    *dst = 0;
    return a;
}
int main() {
    char *a;
    a = argstr();
    a = argword(a, ARGTMP); abspath(SRCPATH, ARGTMP);
    a = argword(a, ARGTMP); abspath(OUTPATH, ARGTMP);
    if (peek(OUTPATH) == 0) { puts_("USAGE: ASM SRC.ASM OUT.BIN\r\n"); return 0; }
    bios(FSDIRBUF, 0, DIRPAGE);
    if (bios(FRESOLVE, SRCPATH, 0) & 256) { asmerr("?no source: "); return 0; }
    savesrc();
    if (bios(FFIND, 0, 0) & 256) { asmerr("?no source: "); return 0; }
    opcindex();
    a = HEADS; while (a < HEADS + 512) { *a = 0; a = a + 1; }
    symp = SYMTAB; orgbase = 0; orgset = 0; err = 0;
    pass = 0; assemble();
    if (err) return 0;
    /* pass 2: resolve the output path now, before the write stream is live */
    bios(FRESOLVE, OUTPATH, 0);
    outdir0 = peek(DIRLBA); outdir1 = peek(DIRN); outdir2 = peek(DIRLBA1);
    strncpy_(outfn, FNAME, 12);
    bios(FDELETE, 0, 0);
    bios(FWOPEN, 0, 0);
    pass = 1; assemble();
    if (err) return 0;
    poke(DIRLBA, outdir0); poke(DIRN, outdir1); poke(DIRLBA1, outdir2);
    strncpy_(FNAME, outfn, 12);
    if (bios(FCLOSE, 0, 0) & 256) { asmerr("?write: "); return 0; }
    puts_("OK\r\n");
    return 0;
}
