/* cc.c - the P8X native C compiler written in C (2026-09-13): the size/speed
 * twin of apps/p8xcc.asm and, because it is written in the subset BOTH
 * compilers accept, a compiler that compiles itself on the machine.
 *
 *     RUN /binc/cc.bin SRC.C >OUT.ASM
 *
 * It generates the SAME text the asm compiler does (verified by compiling the
 * same sources with both on the machine and diffing), so the codegen model is
 * the asm compiler's: a memory accumulator __ax and a temp __t0, GLOBALS in
 * static word slots in one array __V, and LOCALS + PARAMS in a P3 stack frame
 * (SUBP3 #_fr_NAME at entry / ADDP3 at exit; the frame size _fr_NAME is an
 * assembler symbol defined at the function end, so the single streaming pass
 * addresses locals before it knows the frame size). No live-slot saves: each
 * call is self-contained, so recursion is correct. A one-token lookahead lets
 * a bare constant or scalar-variable right operand skip the push/pop (the leaf
 * optimization). Condition mode for if/while/for. Read the asm source for the
 * model; this file mirrors it routine for routine.
 *
 * Common-subset rules this source obeys (host p8cc.py AND the on-board cc):
 * no break / continue, no initialised globals (tables are filled at start),
 * declarations at the top of a function, int compares unsigned (a -1 is
 * 65535, which is why EOF tests compare against -1 and never `< 0`), no
 * casts, no sizeof, no switch, no string literal longer than 127 characters
 * (the on-board lexer's buffer), and no `*p = v` store through a char pointer
 * (the on-board cc stores a word there: byte stores are written `p[0] = v`).
 *
 * Layout: the image at $5900 must end below HEADS; the tables live above it
 * (chain heads, //#use stream states + 512-byte buffers, the local arena, the
 * global arena), the BIOS directory-scan page at DIRPAGE, the source read
 * buffer at $FC00, the C stack down from $F7FF.
 */
//#use abi
//#define ROSTATE  0x1F5E
//#define ROSDRV   0x1F85
//#define HEADS    0xD400
//#define USESTATE 0xD5C0
//#define USEBUF   0xD600
//#define LARENA   0xDA00
//#define LARENAEND 0xDD00
//#define ARENA    0xDD00
//#define ARENAEND 0xF000
//#define DIRPAGE  0xF0
//#define MAXFUNC 250
//#define MAXMAC 250
//#define USELEVELS 2
/* keyword codes */
//#define K_INT 1
//#define K_CHAR 2
//#define K_STRUCT 3
//#define K_IF 4
//#define K_WHILE 5
//#define K_PUTC 6
//#define K_RET 7
//#define K_FOR 8
//#define K_BRK 9
//#define K_CONT 10
//#define K_ELSE 11
//#define K_BIOS 12
//#define K_PUTS 13
//#define K_GETC 14
//#define K_PEEK 15
//#define K_POKE 16
//#define K_ARGSTR 17
/* relational codes */
//#define R_LT 0
//#define R_LE 1
//#define R_GT 2
//#define R_GE 3
//#define R_EQ 4
//#define R_NE 5
/* name tables: 32 heads (2 bytes) each, offsets into HEADS */
//#define HLOC 0
//#define HGLOB 64
//#define HFUNC 128
//#define HMAC 192
//#define HTAG 256
//#define HMEM 320
//#define HUSED 384

char tid[24];               /* the identifier text, NUL-terminated */
char curfn[24];             /* the current function (or tag / global) name */
char idname[24];            /* a factor's identifier */
char namebuf[24];           /* //#use / //#define name */
char path[64];
char apathb[80];
char libpath[48];
char strbuf[128];           /* the current string literal (escapes kept raw) */
int pbf; int pbc;           /* pushback */
int curk;                   /* token kind: 0 EOF, 1 NUM, 2 ID, 3 PUNCT, 4 STRING */
int curv;                   /* number value / punct char */
int cur2;                   /* second char of a two-char punct, else 0 */
int curkw;                  /* keyword code of an identifier, 0 = plain */
int tidlen; int curfnl; int idnamel;
int mkc;                    /* matchkw: the mismatching char */
int nth;                    /* name tables: the head array in use */
char *ntname;               /* the name to find / add */
int ntnlen;
int ntflag;
int ntval;
int ntloc;                  /* add to the local arena */
int arenap; int larenap;
int lastent;                /* the variable entry added last (array mark) */
int fent;                   /* a call's callee entry, 0 = undeclared */
int symidx;                 /* SYMFIND: a global slot, or a local's frame byte offset / a param's K */
int symok; int symrch; int symrar;
int symloc;                 /* 1 = the found symbol is a frame local or param, 0 = a global */
int symparam;               /* 1 = a parameter: its displacement is _fr_<curfn> + symidx */
int lhsidx; int lhsch; int lhsar; int lhsloc; int lhsparam;
int idvarok; int idvaridx; int idvarch; int idvarar; int idvarloc; int idvarparam;
int elchar; int elarr;
int exprchar;               /* the last factor loaded a char-typed value */
int dclchar;
int ischartype;
int slotcnt;                /* GLOBAL slot counter (locals now live in the P3 frame) */
int nloff;                  /* the current function's frame byte offset (next free local) */
int cursp;                  /* bytes pushed on P3 in the current expression (added to (P3+d)) */
int pent[16];               /* the current function's parameter entries (K patched once nparams is known) */
int nparams;
int fcnt; int maccnt;
int lblcnt;
int relop; int relf;
int condf; int condcur; int condlbl; int conddone;
int curbrk; int curcont;
int usemul; int usediv; int usenot; int useshl; int useshr;
int usesp;
int stoff; int tagsize;
int stmemok; int stmemoff; int stmemch;
int sawaddrg;
int biosad;
int bailed;
int vn; int hadh;           /* decimal output */

int gexpr();
int stmt();
int gunary();
int gadd();
int gterm();
int gshift();
int grel();
int gband();
int gbxor();
int gbor();
int gland();
int glor();
int gfact();
int advance();
int advnum(int c);
int emit(char *s);
int bail(char *s);

/* ---- output: assembly text via putchar (SYS_PUTC, redirectable). After a
   bail nothing more is printed: the message is the last thing out. ---- */
int emit(char *s) { if (bailed) return 0; while (*s) { putchar(*s); s = s + 1; } return 0; }
int emitn(char *s, int n) { if (bailed) return 0; while (n) { putchar(*s); s = s + 1; n = n - 1; } return 0; }
int emitnl() { if (bailed) return 0; putchar(10); return 0; }
int endig(int p) {                       /* one decimal digit of vn: how many times p fits */
    int d;
    d = 0;
    while (vn >= p) { vn = vn - p; d = d + 1; }
    if (d || hadh) { putchar(d + 48); hadh = 1; }
    return 0;
}
int emitnum(int v) {                     /* v as decimal, no leading zeros */
    if (bailed) return 0;
    vn = v; hadh = 0;
    endig(10000); endig(1000); endig(100); endig(10);
    putchar(vn + 48);
    return 0;
}
int emslot(int rel) { int n; n = slotbase + rel; return emitnum(n + n); }   /* the byte offset of a slot */
int emnib(int n) { if (n < 10) putchar(n + 48); else putchar(n + 55); return 0; }
int emhex(int v) { if (bailed) return 0; emnib((v >> 4) & 15); emnib(v & 15); return 0; }
int bail(char *s) { if (bailed) return 0; emit(s); bailed = 1; return 0; }

/* ---- strings ---- */
int strcpy_(char *d, char *s) { int n; n = 0; while (*s) { d[0] = *s; d = d + 1; s = s + 1; n = n + 1; } d[0] = 0; return n; }
int strcat_(char *d, char *s) { while (*d) d = d + 1; strcpy_(d, s); return 0; }
int streq(char *a, char *b) { while (*a) { if (*a != *b) return 0; a = a + 1; b = b + 1; } return *b == 0; }

/* ---- name tables: [next:2][len:1][flag:1][val:2][chars] in an arena, chained
   from a 32-way head array by the first character (& 31) ---- */
int nthead() { char *n; int k; n = ntname; k = n[0] & 31; return HEADS + nth + k + k; }
int ntfind() {                           /* -> the entry or 0 */
    int *h; int e; char *p; int k; char *n;
    h = nthead(); e = *h; n = ntname;
    while (e) {
        p = e;
        if (p[2] == ntnlen) {
            k = 0;
            while (k < ntnlen && p[6 + k] == n[k]) k = k + 1;
            if (k == ntnlen) return e;
        }
        h = e; e = *h;
    }
    return 0;
}
int ntfull() { bail("cc: symbol table full"); return 0; }
int ntadd() {                            /* -> the new entry */
    int *h; int e; char *p; int k; char *n; int *w;
    if (ntloc) { e = larenap; if (e + 32 > LARENAEND) return ntfull(); }
    else { e = arenap; if (e + 32 > ARENAEND) return ntfull(); }
    h = nthead(); p = e; w = e;
    *w = *h; *h = e;                     /* next = old head; head = entry */
    p[2] = ntnlen; p[3] = ntflag;
    w = e + 4; *w = ntval;
    n = ntname; k = 0;
    while (k < ntnlen) { p[6 + k] = n[k]; k = k + 1; }
    if (ntloc) larenap = e + 6 + ntnlen; else arenap = e + 6 + ntnlen;
    return e;
}
int ntsettid() { ntname = tid; ntnlen = tidlen; return 0; }
int ntsetcurfn() { ntname = curfn; ntnlen = curfnl; return 0; }
int entval(int e) { int *w; w = e + 4; return *w; }
int entflag(int e) { char *p; p = e; return p[3]; }

/* ---- the lexer: the BIOS read stream, one-char pushback; //#use splicing ---- */
int usestate(int lvl) { return USESTATE + (lvl << 4) - lvl - lvl; }   /* 14 bytes per level */
int savestate() {
    char *s; char *d; int k;
    s = ROSTATE; d = usestate(usesp); k = 0;
    while (k < 13) { d[k] = s[k]; k = k + 1; }
    d[13] = peek(ROSDRV);
    return 0;
}
int restorestate() {
    char *s; char *d; int k;
    d = ROSTATE; s = usestate(usesp); k = 0;
    while (k < 13) { d[k] = s[k]; k = k + 1; }
    poke(ROSDRV, s[13]);
    return 0;
}
int gc() {                               /* the next char, -1 at the end of the source */
    int c;
    if (pbf) { pbf = 0; return pbc; }
    c = bios(FGETB, 0, 0);
    while (c & 256) {                    /* a spliced library ended: the parent resumes */
        if (usesp == 0) return -1;
        usesp = usesp - 1; restorestate();
        c = bios(FGETB, 0, 0);
    }
    return c & 255;
}
int ungc(int c) { pbc = c; pbf = 1; return 0; }
int isdig(int c) { return c >= '0' && c <= '9'; }
int isalp(int c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_'; }
int hexval(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 87;
    if (c >= 'A' && c <= 'F') return c - 55;
    return -1;
}
int skipline() { int c; c = gc(); while (c != -1 && c != 10) c = gc(); return 0; }
int matchkw(char *s) {                   /* do the next chars spell s? (consumed); mkc = the mismatch */
    int c;
    while (*s) { c = gc(); if (c != *s) { mkc = c; return 0; } s = s + 1; }
    return 1;
}
int kwbad() { if (mkc != 10) skipline(); return 0; }
int rdname() {                           /* skip blanks, an identifier -> namebuf; -> the char after it (LF at EOF) */
    int c; int n;
    c = gc(); while (c == ' ') c = gc();
    n = 0;
    while (isalp(c) || isdig(c)) { if (n < 23) { namebuf[n] = c; n = n + 1; } c = gc(); }
    namebuf[n] = 0;
    ntname = namebuf; ntnlen = n;
    if (c == -1) c = 10;
    return c;
}
int douse() {                            /* namebuf: once only; open /lib/lib_NAME.c */
    nth = HUSED;
    if (ntfind()) return 0;
    ntflag = 0; ntloc = 0; ntadd();
    if (usesp >= USELEVELS) return 0;
    strcpy_(libpath, "/lib/lib_"); strcat_(libpath, namebuf); strcat_(libpath, ".c");
    savestate();
    bios(FRESOLVE, libpath, 0);
    if (bios(FOPEN, USEBUF + (usesp << 9), 0) & 256) { restorestate(); return 0; }
    usesp = usesp + 1;
    return 0;
}
int tryuse() {                           /* "//#" consumed: "use NAME" */
    int c;
    if (!matchkw("use")) return kwbad();
    c = rdname();
    if (c != 10) skipline();
    if (ntnlen == 0) return 0;
    return douse();
}
int trydef() {                           /* "//#d" consumed: "efine NAME value" */
    int c;
    if (!matchkw("efine")) return kwbad();
    c = rdname();
    while (c == ' ') c = gc();
    if (c == -1) return 0;
    advnum(c);                           /* the value -> curv */
    if (maccnt >= MAXMAC) return bail("cc: too many //#define macros");
    maccnt = maccnt + 1;
    nth = HMAC; ntval = curv; ntflag = 0; ntloc = 0; ntadd();
    return skipline();
}
int advnum(int c) {                      /* a number starting with c -> curk 1, curv */
    int v; int d;
    v = 0;
    if (c == '0') {
        c = gc();
        if (c == 'x' || c == 'X') {
            c = gc(); d = hexval(c);
            while (d != -1) { v = (v << 4) | d; c = gc(); d = hexval(c); }
            if (c != -1) ungc(c);
            curk = 1; curv = v; return 0;
        }
        if (c != -1) ungc(c);
        c = '0';
    }
    while (isdig(c)) { v = v + v; v = v + (v << 2) + (c - '0'); c = gc(); }
    if (c != -1) ungc(c);
    curk = 1; curv = v;
    return 0;
}
int kwfind() {                           /* curkw = the keyword code of tid (first char + length first) */
    int c; int n;
    curkw = 0; c = tid[0]; n = tidlen;
    if (c == 'i') { if (n == 3) { if (streq(tid, "int")) curkw = K_INT; } else if (n == 2) { if (streq(tid, "if")) curkw = K_IF; } }
    else if (c == 'c') { if (n == 4) { if (streq(tid, "char")) curkw = K_CHAR; } else if (n == 8) { if (streq(tid, "continue")) curkw = K_CONT; } }
    else if (c == 's') { if (n == 6) { if (streq(tid, "struct")) curkw = K_STRUCT; } }
    else if (c == 'w') { if (n == 5) { if (streq(tid, "while")) curkw = K_WHILE; } }
    else if (c == 'p') {
        if (n == 7) { if (streq(tid, "putchar")) curkw = K_PUTC; }
        else if (n == 4) { if (streq(tid, "puts")) curkw = K_PUTS; else if (streq(tid, "peek")) curkw = K_PEEK; else if (streq(tid, "poke")) curkw = K_POKE; }
    }
    else if (c == 'r') { if (n == 6) { if (streq(tid, "return")) curkw = K_RET; } }
    else if (c == 'f') { if (n == 3) { if (streq(tid, "for")) curkw = K_FOR; } }
    else if (c == 'b') { if (n == 5) { if (streq(tid, "break")) curkw = K_BRK; } else if (n == 4) { if (streq(tid, "bios")) curkw = K_BIOS; } }
    else if (c == 'e') { if (n == 4) { if (streq(tid, "else")) curkw = K_ELSE; } }
    else if (c == 'g') { if (n == 7) { if (streq(tid, "getchar")) curkw = K_GETC; } }
    else if (c == 'a') { if (n == 6) { if (streq(tid, "argstr")) curkw = K_ARGSTR; } }
    return 0;
}
int blockc() {                           /* inside a block comment: to the closing star-slash */
    int c;
    c = gc();
    while (c != -1) {
        if (c == '*') {
            c = gc(); while (c == '*') c = gc();
            if (c == '/') return 0;
            if (c == -1) return 0;
        }
        c = gc();
    }
    return 0;
}
int advtok(int c) {                      /* the token starting with the non-blank c */
    int n; int c2; int e;
    if (c == -1) { curk = 0; return 0; }
    if (isdig(c)) return advnum(c);
    if (isalp(c)) {
        n = 0;
        while (isalp(c) || isdig(c)) { if (n < 23) { tid[n] = c; n = n + 1; } c = gc(); }
        tid[n] = 0; tidlen = n;
        if (c != -1) ungc(c);
        if (maccnt) {                    /* a //#define macro -> a NUMBER token */
            ntsettid(); nth = HMAC; e = ntfind();
            if (e) { curk = 1; curv = entval(e); return 0; }
        }
        kwfind(); curk = 2;
        return 0;
    }
    if (c == 39) {                       /* 'c' or '\c' -> a NUMBER token */
        c = gc();
        if (c == 92) {
            c = gc();
            if (c == 'n') c = 10; else if (c == 't') c = 9; else if (c == 'r') c = 13; else if (c == '0') c = 0;
        }
        curv = c; curk = 1; gc();        /* (the closing quote) */
        return 0;
    }
    if (c == 34) {                       /* "string": escapes kept raw, the assembler decodes them */
        n = 0; c = gc();
        while (c != -1 && c != 34) {
            if (n < 127) { strbuf[n] = c; n = n + 1; }
            if (c == 92) { c = gc(); if (c != -1) { if (n < 127) { strbuf[n] = c; n = n + 1; } } }
            c = gc();
        }
        strbuf[n] = 0; curk = 4;
        return 0;
    }
    curk = 3; curv = c; cur2 = 0;        /* punctuation, maybe two chars */
    if (c == '=' || c == '!') { c2 = gc(); if (c2 == '=') cur2 = '='; else if (c2 != -1) ungc(c2); }
    else if (c == '<' || c == '>') { c2 = gc(); if (c2 == '=') cur2 = '='; else if (c2 == c) cur2 = c; else if (c2 != -1) ungc(c2); }
    else if (c == '&' || c == '|') { c2 = gc(); if (c2 == c) cur2 = c; else if (c2 != -1) ungc(c2); }
    else if (c == '+' || c == '-') {
        c2 = gc();
        if (c2 == '=') cur2 = '='; else if (c2 == c) cur2 = c;
        else if (c2 == '>' && c == '-') cur2 = '>';
        else if (c2 != -1) ungc(c2);
    }
    return 0;
}
/* one-token pushback, for the single lookahead the constant-leaf optimization
   needs: peeknextk() reports the token after the current one and buffers it so
   the very next advance() re-yields it, leaving the current token unchanged. */
int havetk; int tkk; int tkv; int tk2; int tkkw; int tklen; char tkid[24];
int sck; int scv; int sc2; int sckw; int sclen; char scid[24];
int pk_k; int pk_v; int pk_2; int pk_kw;   /* the peeked token, exposed to oplevel_peek */
int savecur() { sck = curk; scv = curv; sc2 = cur2; sckw = curkw; sclen = tidlen; strcpy_(scid, tid); return 0; }
int restorecur() { curk = sck; curv = scv; cur2 = sc2; curkw = sckw; tidlen = sclen; strcpy_(tid, scid); return 0; }
int advance() {                          /* the next token: skips blanks, comments, directives */
    int c; int c2;
    if (havetk) { havetk = 0; curk = tkk; curv = tkv; cur2 = tk2; curkw = tkkw; tidlen = tklen; strcpy_(tid, tkid); return 0; }
    if (bailed) { curk = 0; return 0; }
    c = gc();
    while (1) {
        while (c == ' ' || c == 10 || c == 13 || c == 9) c = gc();
        if (c != '/') return advtok(c);
        c2 = gc();
        if (c2 == '/') {                 /* a line comment, maybe a //# directive */
            c2 = gc();
            if (c2 == '#') {
                c2 = gc();
                if (c2 == 'd') trydef();
                else { if (c2 != -1) ungc(c2); tryuse(); }
            }
            else if (c2 != 10) { if (c2 != -1) skipline(); }
            c = gc();
        }
        else if (c2 == '*') { blockc(); c = gc(); }
        else { if (c2 != -1) ungc(c2); return advtok(c); }
    }
}

int crk;                                 /* constright: the constant value */
int peeknextk() {                        /* the token AFTER the current one, into pk_*; current preserved */
    savecur();
    advance();
    pk_k = curk; pk_v = curv; pk_2 = cur2; pk_kw = curkw;
    havetk = 1; tkk = curk; tkv = curv; tk2 = cur2; tkkw = curkw; tklen = tidlen; strcpy_(tkid, tid);
    restorecur();
    return 0;
}
int oplevel_peek() {                     /* precedence of the peeked punct (higher binds tighter), 0 if not a binary op */
    int v; int t;
    if (pk_k != 3) return 0;
    v = pk_v; t = pk_2;
    if (v == '*' || v == '/' || v == '%') { if (t == 0) return 8; return 0; }
    if (v == '+' || v == '-') { if (t == 0) return 7; return 0; }
    if (v == '<') { if (t == '<') return 6; if (t == 0 || t == '=') return 5; return 0; }
    if (v == '>') { if (t == '>') return 6; if (t == 0 || t == '=') return 5; return 0; }
    if (v == '=') { if (t == '=') return 4; return 0; }
    if (v == '!') { if (t == '=') return 4; return 0; }
    if (v == '&') { if (t == 0) return 3; return 1; }
    if (v == '^') { if (t == 0) return 2; return 0; }
    if (v == '|') return 1;
    return 0;
}
int isleaf_next(int level) {             /* is the peeked token an operand boundary (not tighter, not postfix)? */
    int v; int t;
    if (pk_k != 3) return 1;             /* id / num / eof after the operand -> a boundary */
    v = pk_v; t = pk_2;
    if (v == '[' || v == '(' || v == '.') return 0;         /* index / call / member: tighter */
    if (v == '-' && t == '>') return 0;                     /* -> */
    if (v == '+' && t == '+') return 0;                     /* ++ */
    if (v == '-' && t == '-') return 0;                     /* -- */
    if (oplevel_peek() > level) return 0;                   /* a tighter binary operator */
    return 1;
}
int constright(int level) {              /* current is the first token of an operand: a bare constant leaf? */
    if (curk != 1) return 0;             /* not a NUMBER */
    if (curv == 65535) return 0;         /* -1: skip (the k+1 relational form would wrap) */
    peeknextk();
    if (!isleaf_next(level)) return 0;
    crk = curv;
    advance();                           /* consume the constant; current -> the peeked token */
    return 1;
}
int varright(int level) {                /* current is an operand: a bare SCALAR variable leaf? sym* describes it */
    if (curk != 2) return 0;             /* not an identifier */
    if (curkw != 0) return 0;            /* a keyword / builtin */
    symfind();
    if (symok == 0) return 0;            /* undeclared: let the normal path emit the error */
    if (symrar) return 0;                /* an array name decays to an address: not this path */
    peeknextk();
    if (!isleaf_next(level)) return 0;
    advance();                           /* consume the identifier; sym* is the leaf */
    return 1;
}

/* ---- symbols: locals (HLOC, per function), globals, functions, struct tags
   and members. Entry flag: bit0 char, bit1 array (functions: the parameter
   count); value: the slot / size / offset / base slot. ---- */
int symfind() {                          /* tid: a local/param, else a global */
    int e; int f;
    ntsettid(); nth = HLOC; e = ntfind();
    if (e) {
        symidx = entval(e); symloc = 1;
        f = entflag(e); symparam = (f >> 2) & 1;
    } else {
        nth = HGLOB; e = ntfind();
        if (e == 0) { symok = 0; return 0; }
        symidx = entval(e); symloc = 0; symparam = 0;
        f = entflag(e);
    }
    symrch = f & 1; symrar = (f >> 1) & 1; symok = 1;
    return 0;
}
int symadd() {                           /* a local named tid at the current frame offset nloff (bytes) */
    ntsettid(); nth = HLOC; ntflag = dclchar; ntval = nloff; ntloc = 1;
    lastent = ntadd(); symidx = nloff; symloc = 1; symparam = 0;
    return 0;
}
int setentval(int e, int v) { int *w; w = e + 4; *w = v; return 0; }
int gsymadd() { ntsetcurfn(); nth = HGLOB; ntflag = dclchar; ntval = slotcnt; ntloc = 0; lastent = ntadd(); return 0; }
int markarr() { char *p; p = lastent; p[3] = p[3] | 2; return 0; }
int cpcurfn() { strcpy_(curfn, tid); curfnl = tidlen; return 0; }
int cpidname() { strcpy_(idname, tid); idnamel = tidlen; return 0; }
int fadd() {
    if (fcnt >= MAXFUNC) return bail("cc: too many functions");
    fcnt = fcnt + 1;
    ntsetcurfn(); nth = HFUNC; ntflag = nparams; ntval = 0; ntloc = 0; ntadd();
    return 0;
}
int emitfname() {                        /* the callee: its entry's name, or the identifier itself */
    char *p;
    if (fent == 0) return emit(idname);
    p = fent;
    return emitn(p + 6, p[2]);
}
int stagadd() { ntsetcurfn(); nth = HTAG; ntval = stoff; ntflag = 0; ntloc = 0; ntadd(); return 0; }
int stagfind() { int e; nth = HTAG; e = ntfind(); tagsize = 0; if (e) tagsize = entval(e); return 0; }
int stmadd() { ntsettid(); nth = HMEM; ntflag = dclchar; ntval = stoff; ntloc = 0; ntadd(); return 0; }
int stmfind() {
    int e;
    ntsettid(); nth = HMEM; e = ntfind(); stmemok = 0;
    if (e) { stmemoff = entval(e); stmemch = entflag(e); stmemok = 1; }
    return 0;
}
int clearloc() { int *h; int k; larenap = LARENA; h = HEADS + HLOC; k = 0; while (k < 32) { h[k] = 0; k = k + 1; } return 0; }

/* ---- emit helpers: the code shapes ---- */
/* emfp: "(P3+<disp>)" for the current symbol -- a frame local (disp = offset +
   cursp) or a parameter (disp = _fr_<curfn> + K + cursp). emgb: a global's
   byte offset in __V (slot * 2). Both read the sym* fields. */
int emfp() {                             /* a frame local past disp 255 would silently truncate: bail loudly */
    if (symparam == 0) { if (symidx + cursp > 255) return bail("cc: frame local over 255 bytes (recursion+big array: use /bin/cc)"); }
    emit("(P3+"); if (symparam) { emit("_fr_"); emit(curfn); emit("+"); } emitnum(symidx + cursp); return emit(")");
}
int emgb() { return emitnum(symidx + symidx); }
int em_ldvar() {
    if (symloc) { emit("\tLDW __ax,"); emfp(); return emitnl(); }
    emit("\tMOVW __ax,__V+"); emgb(); return emitnl();
}
int em_stvar() {                          /* store __ax -> the LHS (lhsidx/lhsloc/lhsparam) */
    int sl; int sp; int si;
    sl = symloc; sp = symparam; si = symidx;
    symloc = lhsloc; symparam = lhsparam; symidx = lhsidx;
    if (symloc) { emit("\tSTW "); emfp(); emit(",__ax\n"); }
    else { emit("\tMOVW __V+"); emgb(); emit(",__ax\n"); }
    symloc = sl; symparam = sp; symidx = si;
    return 0;
}
int em_addrof() {
    if (symloc) { emit("\tLEAW __ax,"); emfp(); return emitnl(); }
    emit("\tLDA #<__V+"); emgb(); emit("\n\tSTA __ax\n\tLDA #>__V+"); emgb(); return emit("\n\tSTA __ax+1\n");
}
int em_incvar() {                         /* ++ the variable in place; a frame slot goes via __t0 (INCW is abs-only) */
    if (symloc) { emit("\tLDW __t0,"); emfp(); emit("\n\tINCW __t0\n\tSTW "); emfp(); return emit(",__t0\n"); }
    emit("\tINCW __V+"); emgb(); return emitnl();
}
int em_decvar() {
    if (symloc) { emit("\tLDW __t0,"); emfp(); emit("\n\tDECW __t0\n\tSTW "); emfp(); return emit(",__t0\n"); }
    emit("\tDECW __V+"); emgb(); return emitnl();
}
int em_push() { cursp = cursp + 2; return emit("\tPHW __ax\n"); }
int em_pop() { cursp = cursp - 2; return emit("\tPLW __t0\n"); }
int em_ax0() { return emit("\tLDW __ax,#0\n"); }
int em_ax1() { return emit("\tLDW __ax,#1\n"); }
int em_testax() { return emit("\tCMPW __ax,#0\n"); }
int em_addp3(int n) { emit("\tADDP3 #"); emitnum(n); return emitnl(); }
int em_loadb() { return emit("\tLPW1 __ax\n\tLDA (P1)\n\tSTA __ax\n\tLDA #0\n\tSTA __ax+1\n"); }
int em_storeb() { return emit("\tLPW1 __t0\n\tLDA __ax\n\tSTA (P1)\n"); }
int em_loadw() { return emit("\tLPW1 __ax\n\tLDA (P1)\n\tSTA __ax\n\tINP1\n\tLDA (P1)\n\tSTA __ax+1\n"); }
int em_storew() { return emit("\tLPW1 __t0\n\tLDA __ax\n\tSTA (P1)\n\tINP1\n\tLDA __ax+1\n\tSTA (P1)\n"); }
int em_scale2() { return emit("\tLDA __ax\n\tSHL\n\tSTA __ax\n\tLDA __ax+1\n\tROL\n\tSTA __ax+1\n"); }
int em_addoff(int off) { if (off == 0) return 0; emit("\tADDW __ax,#"); emitnum(off); return emitnl(); }
int em_addimm(int k) { k = k & 65535; if (k == 0) return 0; if (k == 1) return emit("\tINCW __ax\n"); emit("\tADDW __ax,#"); emitnum(k); return emitnl(); }
int em_subimm(int k) { k = k & 65535; if (k == 0) return 0; if (k == 1) return emit("\tDECW __ax\n"); emit("\tSUBW __ax,#"); emitnum(k); return emitnl(); }
int em_wimm(char *mn, int k) { emit("\t"); emit(mn); emit(" __ax,#"); emitnum(k & 65535); return emitnl(); }
int leaf_t() {                           /* __t0 = value of the sym* leaf variable (from varright) */
    if (symloc) { emit("\tLDW __t0,"); emfp(); return emitnl(); }
    emit("\tMOVW __t0,__V+"); emgb(); return emitnl();
}
int newlbl() { lblcnt = lblcnt + 1; return lblcnt - 1; }
int emitj(char *j, int l) { emit(j); emitnum(l); return emitnl(); }
int emitlbl(int l) { if (bailed) return 0; putchar('L'); emitnum(l); return emit(":\n"); }

/* ---- the parser (single pass; emits as it parses) ---- */
int ispunct(int c) { return curk == 3 && cur2 == 0 && curv == c; }
int istwo(int c) { return curk == 3 && curv == c && cur2 == c; }
int synerr() { return bail("cc: syntax error"); }
int expectp(int c) { if (!ispunct(c)) return synerr(); return advance(); }
int skipstars() { while (ispunct('*')) advance(); return 0; }
int expecttype() {                       /* int / char (ischartype), advance past it */
    ischartype = 0;
    if (curk != 2) return synerr();
    if (curkw == K_CHAR) ischartype = 1;
    else if (curkw != K_INT) return synerr();
    return advance();
}
int elemaddr() {                         /* symidx = an array / pointer; '[' current: the element address -> __ax */
    if (elarr) em_addrof(); else em_ldvar();
    em_push();
    advance();
    gexpr();
    expectp(']');
    if (elchar == 0) em_scale2();
    em_pop();
    return emit("\tADDW __ax,__t0\n");
}
int reldet() {                           /* the current punct a relational? relf, relop */
    relf = 0;
    if (curv == '<') { if (cur2 == 0) relop = R_LT; else if (cur2 == '=') relop = R_LE; else return 0; }
    else if (curv == '>') { if (cur2 == 0) relop = R_GT; else if (cur2 == '=') relop = R_GE; else return 0; }
    else if (curv == '=') { if (cur2 != '=') return 0; relop = R_EQ; }
    else if (curv == '!') { if (cur2 != '=') return 0; relop = R_NE; }
    else return 0;
    relf = 1;
    return 0;
}
int emitcf() {                           /* branch to condlbl when the relation is FALSE */
    if (relop == R_LT || relop == R_GT) return emitj("\tJC L", condlbl);
    if (relop == R_EQ) return emitj("\tJNZ L", condlbl);
    if (relop == R_NE) return emitj("\tJZ L", condlbl);
    return emitj("\tJNC L", condlbl);
}
int emitcmp() {                          /* the 0/1 value of the relation */
    int la; int lb;
    la = newlbl(); lb = newlbl();
    if (relop == R_LT || relop == R_GT) emitj("\tJNC L", la);
    else if (relop == R_GE || relop == R_LE) emitj("\tJC L", la);
    else if (relop == R_EQ) emitj("\tJZ L", la);
    else emitj("\tJNZ L", la);
    em_ax0(); emitj("\tJMP L", lb); emitlbl(la); em_ax1(); emitlbl(lb);
    return 0;
}
int grel() {                             /* sh [relop sh] -> 0/1, or in condition mode one branch */
    int r; int rr; int kk;
    gshift();
    if (curk != 3) return 0;
    reldet();
    if (relf == 0) return 0;
    r = relop;
    advance();                           /* past the relop; current = the right operand */
    if (constright(5)) {                 /* right is a constant: CMPW __ax,#k (>,<= compare against k+1) */
        rr = r; kk = crk;
        if (r == R_GT) { rr = R_GE; kk = crk + 1; }
        else if (r == R_LE) { rr = R_LT; kk = crk + 1; }
        emit("\tCMPW __ax,#"); emitnum(kk); emitnl();
        relop = rr;
    } else if (varright(5)) {            /* right is a scalar variable: L in __ax, R in __t0 */
        leaf_t(); relop = r;
        if (relop >= R_EQ) emit("\tJSR __cmp\n");
        else if (relop == R_LE || relop == R_GT) emit("\tCMPW __t0,__ax\n");   /* C = (R >= L) */
        else emit("\tCMPW __ax,__t0\n");                                       /* C = (L >= R) */
    } else {                             /* the general two-operand compare: __t0 = L, __ax = R */
        em_push(); gshift(); relop = r; em_pop();
        if (relop >= R_EQ) emit("\tJSR __cmp\n");
        else if (relop == R_LE || relop == R_GT) emit("\tCMPW __ax,__t0\n");
        else emit("\tCMPW __t0,__ax\n");
    }
    if (condcur) { if (ispunct(')') || ispunct(';')) { emitcf(); conddone = 1; return 0; } }
    return emitcmp();
}
int gshift() {
    gadd();
    while (istwo('<') || istwo('>')) {
        if (curv == '<') { useshl = 1; advance(); em_push(); gadd(); em_pop(); emit("\tJSR __shl\n"); }
        else { useshr = 1; advance(); em_push(); gadd(); em_pop(); emit("\tJSR __shr\n"); }
    }
    return 0;
}
int gadd() {
    int plus;
    gterm();
    while (ispunct('+') || ispunct('-')) {
        plus = (curv == '+'); advance();
        if (constright(7)) { if (plus) em_addimm(crk); else em_subimm(crk); }
        else if (varright(7)) { leaf_t(); if (plus) emit("\tADDW __ax,__t0\n"); else emit("\tSUBW __ax,__t0\n"); }
        else if (plus) { em_push(); gterm(); em_pop(); emit("\tADDW __ax,__t0\n"); }
        else { em_push(); gterm(); em_pop(); emit("\tSUBW __t0,__ax\n\tMOVW __ax,__t0\n"); }
    }
    return 0;
}
int gterm() {
    gunary();
    while (ispunct('*') || ispunct('/') || ispunct('%')) {
        if (curv == '*') { usemul = 1; advance(); em_push(); gunary(); em_pop(); emit("\tJSR __mul\n"); }
        else if (curv == '/') { usediv = 1; advance(); em_push(); gunary(); em_pop(); emit("\tJSR __div\n"); }
        else { usediv = 1; advance(); em_push(); gunary(); em_pop(); emit("\tJSR __mod\n"); }
    }
    return 0;
}
int gunary() {                           /* ('-' | '!' | '&' | '*' | '++' | '--') unary | factor */
    if (curk != 3) return gfact();
    if (cur2) {
        if (istwo('+')) { advance(); symfind(); if (symok == 0) return gfact(); em_incvar(); em_ldvar(); return advance(); }
        if (istwo('-')) { advance(); symfind(); if (symok == 0) return gfact(); em_decvar(); em_ldvar(); return advance(); }
        return gfact();
    }
    if (curv == '-') { advance(); gunary(); return emit("\tXORW __ax,#65535\n\tINCW __ax\n"); }
    if (curv == '!') { advance(); gunary(); usenot = 1; return emit("\tJSR __lnot\n"); }
    if (curv == '*') { advance(); gunary(); if (exprchar) return em_loadb(); return em_loadw(); }
    if (curv == '&') {
        sawaddrg = 1;
        advance(); symfind();
        if (symok == 0) return 0;
        idvaridx = symidx; idvarch = symrch; idvarar = symrar; idvarloc = symloc; idvarparam = symparam;
        advance();
        symidx = idvaridx; symloc = idvarloc; symparam = idvarparam;
        if (ispunct('[')) { elchar = idvarch; elarr = idvarar; return elemaddr(); }
        return em_addrof();
    }
    return gfact();
}
int gc_builtin();
int gfi_call();
int gfi_memld() {                        /* . or -> consumed next: the member value */
    advance(); stmfind(); em_addoff(stmemoff); advance();
    if (stmemch) return em_loadb();
    return em_loadw();
}
int gfact() {
    int dl; int sl;
    if (curk == 1) {
        emit("\tLDW __ax,#"); emitnum(curv); emitnl();
        exprchar = 0;
        return advance();
    }
    if (curk == 4) {                     /* a string literal: its bytes inline, jumped over */
        exprchar = 1;
        dl = newlbl(); sl = newlbl();
        emitj("\tJMP L", sl); emitlbl(dl);
        emit("\t.asciiz \""); emit(strbuf); emit("\"\n\t.byte 0\n");
        emitlbl(sl);
        emit("\tLDA #<L"); emitnum(dl); emit("\n\tSTA __ax\n\tLDA #>L"); emitnum(dl); emit("\n\tSTA __ax+1\n");
        return advance();
    }
    if (curk == 2) {
        if (curkw >= K_BIOS) return gc_builtin();
        cpidname();
        symfind();
        idvarok = symok; idvaridx = symidx; idvarch = symrch; idvarar = symrar; idvarloc = symloc; idvarparam = symparam;
        advance();
        if (curk == 3) {
            if (cur2 == 0) {
                if (curv == '(') return gfi_call();
                if (curv == '[') { symidx = idvaridx; symloc = idvarloc; symparam = idvarparam; elchar = idvarch; elarr = idvarar; elemaddr(); if (elchar) return em_loadb(); return em_loadw(); }
                if (curv == '.') { symidx = idvaridx; symloc = idvarloc; symparam = idvarparam; em_addrof(); return gfi_memld(); }
            }
            else if (curv == '-') {
                if (cur2 == '>') { symidx = idvaridx; symloc = idvarloc; symparam = idvarparam; em_ldvar(); return gfi_memld(); }
                if (cur2 == '-') { if (idvarok == 0) return 0; symidx = idvaridx; symloc = idvarloc; symparam = idvarparam; em_ldvar(); em_decvar(); return advance(); }
            }
            else if (curv == '+') {
                if (cur2 == '+') { if (idvarok == 0) return 0; symidx = idvaridx; symloc = idvarloc; symparam = idvarparam; em_ldvar(); em_incvar(); return advance(); }
            }
        }
        if (idvarok == 0) return 0;
        symidx = idvaridx; symloc = idvarloc; symparam = idvarparam; exprchar = idvarch;
        if (idvarar) { sawaddrg = 1; return em_addrof(); }   /* a bare array name decays to its address */
        return em_ldvar();
    }
    if (ispunct('(')) { advance(); gexpr(); return expectp(')'); }
    return 0;
}
int gc_builtin() {                       /* bios / puts / getchar / peek / poke / argstr */
    int l;
    if (curkw == K_PUTS) { advance(); expectp('('); gexpr(); expectp(')'); return emit("\tLPW1 __ax\n\tJSR $200F\n\tLDA #10\n\tJSR $2009\n"); }
    if (curkw == K_GETC) {
        advance(); expectp('('); expectp(')');
        emit("\tJSR $200C\n\tSTA __ax\n\tLDA #0\n\tSTA __ax+1\n");
        l = newlbl(); emitj("\tJNC L", l);
        emit("\tLDA #255\n\tSTA __ax\n\tSTA __ax+1\n");
        return emitlbl(l);
    }
    if (curkw == K_PEEK) { advance(); expectp('('); gexpr(); expectp(')'); return em_loadb(); }
    if (curkw == K_POKE) { advance(); expectp('('); gexpr(); em_push(); expectp(','); gexpr(); em_pop(); em_storeb(); return expectp(')'); }
    if (curkw == K_ARGSTR) { advance(); expectp('('); expectp(')'); return emit("\tTPA2L\n\tSTA __ax\n\tTPA2H\n\tSTA __ax+1\n"); }
    if (curkw != K_BIOS) return synerr();
    advance(); expectp('(');             /* bios(ADDR, p1, a) -> A | carry<<8 */
    biosad = curv; advance();
    expectp(','); gexpr(); em_push();
    expectp(','); gexpr(); expectp(')');
    em_pop();
    emit("\tLPW1 __t0\n\tLDA __ax\n\tJSR $"); emhex(biosad >> 8); emhex(biosad); emitnl();
    emit("\tSTA __ax\n");
    l = newlbl();
    emit("\tLDA #0\n"); emitj("\tJNC L", l); emit("\tLDA #1\n"); emitlbl(l);
    return emit("\tSTA __ax+1\n");
}
int gfi_call() {                         /* idname ( args ): the current token is '(' */
    int e; int n;                        /* frames make each call self-contained: no slot saves */
    ntname = idname; ntnlen = idnamel; nth = HFUNC; e = ntfind();
    advance();
    n = 0;
    if (!ispunct(')')) {                  /* args left to right; each PHW deepens cursp */
        gexpr(); em_push(); n = 1;
        while (ispunct(',')) { advance(); gexpr(); em_push(); n = n + 1; }
    }
    expectp(')');
    emit("\tJSR _f_"); fent = e; emitfname(); emitnl();
    if (n) { em_addp3(n + n); cursp = cursp - (n + n); }   /* drop the pushed args */
    return 0;
}
int gexpr() {                            /* condition mode is consumed here (a nested gexpr sees 0) */
    int tf; int te;
    condcur = condf; condf = 0; conddone = 0;
    glor();
    if (!ispunct('?')) return 0;
    advance(); em_testax();
    tf = newlbl(); te = newlbl();
    emitj("\tJZ L", tf);
    gexpr();
    expectp(':');
    emitj("\tJMP L", te); emitlbl(tf);
    gexpr();
    return emitlbl(te);
}
int glor() {
    int lt; int le;
    gland();
    while (istwo('|')) {
        lt = newlbl(); le = newlbl();
        em_testax(); emitj("\tJNZ L", lt);
        advance(); gland();
        em_testax(); emitj("\tJNZ L", lt);
        em_ax0(); emitj("\tJMP L", le); emitlbl(lt); em_ax1(); emitlbl(le);
    }
    return 0;
}
int gland() {
    int lf; int le;
    gbor();
    while (istwo('&')) {
        condcur = 0;                     /* the right operand is a value: no condition-mode branch */
        lf = newlbl(); le = newlbl();
        em_testax(); emitj("\tJZ L", lf);
        advance(); gbor();
        em_testax(); emitj("\tJZ L", lf);
        em_ax1(); emitj("\tJMP L", le); emitlbl(lf); em_ax0(); emitlbl(le);
    }
    return 0;
}
int gbor() { gbxor(); while (ispunct('|')) { advance(); if (constright(1)) em_wimm("ORW", crk); else if (varright(1)) { leaf_t(); emit("\tORW __ax,__t0\n"); } else { em_push(); gbxor(); em_pop(); emit("\tORW __ax,__t0\n"); } } return 0; }
int gbxor() { gband(); while (ispunct('^')) { advance(); if (constright(2)) em_wimm("XORW", crk); else if (varright(2)) { leaf_t(); emit("\tXORW __ax,__t0\n"); } else { em_push(); gband(); em_pop(); emit("\tXORW __ax,__t0\n"); } } return 0; }
int gband() { grel(); while (ispunct('&')) { advance(); if (constright(3)) em_wimm("ANDW", crk); else if (varright(3)) { leaf_t(); emit("\tANDW __ax,__t0\n"); } else { em_push(); grel(); em_pop(); emit("\tANDW __ax,__t0\n"); } } return 0; }

/* ---- statements ---- */
int cond(int lbl) {                      /* ( condition ) in condition mode; the false label */
    condlbl = lbl;
    expectp('('); condf = 1; gexpr(); expectp(')');
    if (conddone) return 0;
    em_testax();
    return emitj("\tJZ L", lbl);
}
int st_if() {
    int la; int lb;
    advance(); la = newlbl();
    cond(la);
    stmt();
    if (curk == 2) {
        if (curkw == K_ELSE) {
            advance(); lb = newlbl();
            emitj("\tJMP L", lb); emitlbl(la);
            stmt();
            return emitlbl(lb);
        }
    }
    return emitlbl(la);
}
int st_while() {
    int lt; int le; int sb; int sc;
    advance(); lt = newlbl(); le = newlbl();
    emitlbl(lt);
    cond(le);
    sb = curbrk; sc = curcont; curbrk = le; curcont = lt;
    stmt();
    curbrk = sb; curcont = sc;
    emitj("\tJMP L", lt);
    return emitlbl(le);
}
int forclause() {                        /* an optional NAME = expr */
    if (curk != 2) return 0;
    symfind(); if (symok == 0) return 0;
    lhsidx = symidx; lhsloc = symloc; lhsparam = symparam;
    advance(); expectp('='); gexpr();
    return em_stvar();
}
int st_for() {                           /* init; Ltop: cond JZ Lend; JMP Lbody; Lpost: post; JMP Ltop; Lbody: body; JMP Lpost; Lend: */
    int lt; int lb; int lp; int le; int sb; int sc;
    advance(); expectp('(');
    lt = newlbl(); lb = newlbl(); lp = newlbl(); le = newlbl();
    forclause(); expectp(';');
    emitlbl(lt);
    if (!ispunct(';')) {
        condlbl = le; condf = 1; gexpr();
        if (conddone == 0) { em_testax(); emitj("\tJZ L", le); }
    }
    expectp(';');
    emitj("\tJMP L", lb); emitlbl(lp);
    forclause(); expectp(')');
    emitj("\tJMP L", lt); emitlbl(lb);
    sb = curbrk; sc = curcont; curbrk = le; curcont = lp;
    stmt();
    curbrk = sb; curcont = sc;
    emitj("\tJMP L", lp);
    return emitlbl(le);
}
int st_decl() {                          /* type [*]NAME [= expr] ;  |  type NAME[N] ; -- a frame local */
    int n;
    dclchar = 0; if (curkw == K_CHAR) dclchar = 1;
    advance(); skipstars();
    symadd(); lhsidx = symidx; lhsloc = 1; lhsparam = 0;    /* the base frame offset */
    advance();
    if (ispunct('[')) {                  /* an array: char[n] = n bytes, int[n] = 2n bytes */
        advance();
        n = curv;
        if (dclchar) nloff = nloff + n; else nloff = nloff + n + n;
        markarr();
        advance(); expectp(']');
    }
    else {
        nloff = nloff + 2;               /* a scalar / pointer: one 2-byte frame slot */
        if (ispunct('=')) { advance(); gexpr(); em_stvar(); }
    }
    return expectp(';');
}
int st_lstruct() {                       /* struct Tag [*]NAME ; -- a frame local */
    advance(); ntsettid(); stagfind(); advance();
    dclchar = 0;
    if (ispunct('*')) {                  /* a pointer: skip the stars, then the name is one 2-byte slot */
        skipstars();
        symadd(); nloff = nloff + 2;
    }
    else {                               /* a value: the struct's bytes */
        symadd(); nloff = nloff + tagsize;
    }
    advance();
    return expectp(';');
}
int sa_cload() { symidx = lhsidx; symloc = lhsloc; symparam = lhsparam; em_ldvar(); em_push(); advance(); gexpr(); return em_pop(); }
int sa_memst() {                         /* the member store: . or -> consumed next, __ax = the base */
    int w;
    advance(); stmfind(); em_addoff(stmemoff); advance();
    w = stmemch;
    em_push(); expectp('='); gexpr(); em_pop();
    if (w) em_storeb(); else em_storew();
    return expectp(';');
}
int st_assign() {                        /* NAME = e; [i] = e; .m = e; ->m = e; ++; --; += e; -= e; or an expression */
    int w;
    symfind();
    if (symok == 0) { gexpr(); return expectp(';'); }
    lhsidx = symidx; lhsch = symrch; lhsar = symrar; lhsloc = symloc; lhsparam = symparam;
    advance();
    if (curk != 3) return synerr();
    if (cur2) {
        if (curv == '-') {
            if (cur2 == '>') { symidx = lhsidx; symloc = lhsloc; symparam = lhsparam; em_ldvar(); return sa_memst(); }
            if (cur2 == '-') { symidx = lhsidx; symloc = lhsloc; symparam = lhsparam; advance(); em_decvar(); return expectp(';'); }
            sa_cload(); emit("\tSUBW __t0,__ax\n\tMOVW __ax,__t0\n"); em_stvar(); return expectp(';');
        }
        if (curv != '+') return synerr();
        if (cur2 == '+') { symidx = lhsidx; symloc = lhsloc; symparam = lhsparam; advance(); em_incvar(); return expectp(';'); }
        sa_cload(); emit("\tADDW __ax,__t0\n"); em_stvar(); return expectp(';');
    }
    if (curv == '[') {
        symidx = lhsidx; symloc = lhsloc; symparam = lhsparam; elchar = lhsch; elarr = lhsar;
        elemaddr(); w = elchar;
        em_push(); expectp('='); gexpr(); em_pop();
        if (w) em_storeb(); else em_storew();
        return expectp(';');
    }
    if (curv == '.') { symidx = lhsidx; symloc = lhsloc; symparam = lhsparam; em_addrof(); return sa_memst(); }
    expectp('='); gexpr(); em_stvar();
    return expectp(';');
}
int stmt() {
    cursp = 0;                           /* each statement's expressions balance the P3 pushes */
    if (curk == 3) {
        if (cur2) return synerr();
        if (curv == '{') {
            advance();
            while (!ispunct('}')) { if (curk == 0) return synerr(); stmt(); }
            return advance();
        }
        if (curv == '*') { advance(); gunary(); em_push(); expectp('='); gexpr(); em_pop(); em_storew(); return expectp(';'); }
        if (curv == ';') return advance();
        return synerr();
    }
    if (curk != 2) return synerr();
    if (curkw == 0 || curkw >= K_BIOS) return st_assign();
    if (curkw == K_INT || curkw == K_CHAR) return st_decl();
    if (curkw == K_IF) return st_if();
    if (curkw == K_WHILE) return st_while();
    if (curkw == K_FOR) return st_for();
    if (curkw == K_RET) {
        advance();
        if (!ispunct(';')) gexpr();
        expectp(';');
        emit("\tJMP _e_"); emit(curfn); return emitnl();
    }
    if (curkw == K_PUTC) { advance(); expectp('('); gexpr(); expectp(')'); expectp(';'); return emit("\tLDA __ax\n\tJSR $2009\n"); }
    if (curkw == K_BRK) { advance(); emitj("\tJMP L", curbrk); return expectp(';'); }
    if (curkw == K_CONT) { advance(); emitj("\tJMP L", curcont); return expectp(';'); }
    if (curkw == K_STRUCT) return st_lstruct();
    return synerr();
}

/* ---- top level ---- */
int sdf_body() {                         /* struct TAG { members } ; with curfn = the tag */
    expectp('{'); stoff = 0;
    while (!ispunct('}')) {
        if (curk == 0) return synerr();
        expecttype(); dclchar = ischartype;
        if (ispunct('*')) { dclchar = 0; skipstars(); }
        stmadd(); advance();
        if (dclchar) stoff = stoff + 1; else stoff = stoff + 2;
        expectp(';');
    }
    expectp('}'); stagadd();
    return expectp(';');
}
int fd_struct() {                        /* top level 'struct': a definition, or a global struct variable */
    int isptr;
    advance(); cpcurfn(); advance();
    if (ispunct('{')) return sdf_body();
    ntsetcurfn(); stagfind();
    dclchar = 0; isptr = 0;
    if (ispunct('*')) { skipstars(); isptr = 1; }
    cpcurfn(); gsymadd();
    if (isptr) slotcnt = slotcnt + 1; else slotcnt = slotcnt + ((tagsize + 1) >> 1);
    advance();
    return expectp(';');
}
int fd_glob() {                          /* a global: type [*]NAME [ [N] ] ; */
    int n;
    gsymadd();
    if (ispunct('[')) {
        markarr(); advance();
        n = curv; if (dclchar) n = (n + 1) >> 1;
        slotcnt = slotcnt + n;
        advance(); expectp(']');
    }
    else slotcnt = slotcnt + 1;
    return expectp(';');
}
int paramadd() {                         /* add the parameter TID to the frame table (K patched later) */
    ntsettid(); nth = HLOC; ntflag = dclchar | 4; ntval = 0; ntloc = 1;
    pent[nparams] = ntadd();
    return 0;
}
int funcdef() {                          /* one top-level item */
    int i;
    if (curk != 2) return synerr();
    if (curkw == K_STRUCT) return fd_struct();
    expecttype(); dclchar = ischartype;
    skipstars();
    cpcurfn(); advance();
    if (!ispunct('(')) return fd_glob();
    nloff = 1; nparams = 0; cursp = 0; clearloc();   /* first local at P3+1 (P3+0 is the boundary; ret at P3+1..2 grows over it) */
    advance();
    if (!ispunct(')')) {
        expecttype(); dclchar = ischartype; skipstars(); paramadd(); advance(); nparams = nparams + 1;
        while (ispunct(',')) { advance(); expecttype(); dclchar = ischartype; skipstars(); paramadd(); advance(); nparams = nparams + 1; }
    }
    expectp(')');
    fadd();
    if (ispunct(';')) return advance();  /* a prototype only registers the name */
    /* nparams is known now: the return area is 3 bytes (boundary + 2-byte
       return address), so param i lives at (P3 + _fr_<fn> + 3 + 2*(nparams-1-i)) */
    i = 0;
    while (i < nparams) { setentval(pent[i], 3 + 2 * (nparams - 1 - i)); i = i + 1; }
    emit("_f_"); emit(curfn); emit(":\n\tSUBP3 #_fr_"); emit(curfn); emitnl();   /* reserve the frame */
    expectp('{');
    while (!ispunct('}')) { if (curk == 0) return synerr(); stmt(); }
    expectp('}');
    /* params sit above the locals at _fr + 3 + 2*(nparams-1-i); if the whole
       frame + param area nears the 255 disp limit it would truncate: bail */
    if (nloff + nparams + nparams > 231) return bail("cc: frame + params over 255 bytes (use /bin/cc)");
    emit("_e_"); emit(curfn); emit(":\n\tADDP3 #_fr_"); emit(curfn); emit("\n\tRTS\n");
    emit("_fr_"); emit(curfn); emit(" = "); emitnum(nloff & 65534); emitnl();   /* the frame size = (nloff-1) rounded up to even */
    return 0;
}
/* the runtime helpers, emitted once each when the program needs them (in
   pieces: a string literal is at most 127 characters) */
int rt_mul() {
    emit("__mul:\tLDA #0\n\tSTA __mr\n\tSTA __mr+1\n__mu0:\tLDA __ax\n\tLDB __ax+1\n\tOR\n\tJZ __mu2\n");
    emit("\tLDA __mr\n\tLDB __t0\n\tADD\n\tSTA __mr\n\tLDA #0\n\tJNC __mu1\n\tLDA #1\n__mu1:\tSTA __c\n");
    emit("\tLDA __mr+1\n\tLDB __t0+1\n\tADD\n\tLDB __c\n\tADD\n\tSTA __mr+1\n\tLDA __ax\n\tLDB #1\n\tSUB\n");
    emit("\tSTA __ax\n\tJC __mu0\n\tLDA __ax+1\n\tDEC\n\tSTA __ax+1\n\tJMP __mu0\n");
    return emit("__mu2:\tLDA __mr\n\tSTA __ax\n\tLDA __mr+1\n\tSTA __ax+1\n\tRTS\n__mr:   .fill 2\n");
}
int rt_div() {
    emit("__div:\tJSR __divmod\n\tLDA __dq\n\tSTA __ax\n\tLDA __dq+1\n\tSTA __ax+1\n\tRTS\n");
    emit("__mod:\tJSR __divmod\n\tLDA __dr\n\tSTA __ax\n\tLDA __dr+1\n\tSTA __ax+1\n\tRTS\n");
    emit("__divmod:\tLDA __t0\n\tSTA __dr\n\tLDA __t0+1\n\tSTA __dr+1\n\tLDA #0\n\tSTA __dq\n\tSTA __dq+1\n");
    emit("\tLDA __ax\n\tLDB __ax+1\n\tOR\n\tJZ __dm2\n__dm0:\tLDA __dr+1\n\tLDB __ax+1\n\tCMP\n\tJNZ __dm3\n");
    emit("\tLDA __dr\n\tLDB __ax\n\tCMP\n__dm3:\tJNC __dm2\n\tLDA __dr\n\tLDB __ax\n\tSUB\n\tSTA __dr\n");
    emit("\tLDA #0\n\tJC __dm1\n\tLDA #1\n__dm1:\tSTA __c\n\tLDA __dr+1\n\tLDB __ax+1\n\tSUB\n\tSTA __dr+1\n");
    emit("\tLDA __c\n\tJZ __dm4\n\tLDA __dr+1\n\tDEC\n\tSTA __dr+1\n__dm4:\tLDA __dq\n\tLDB #1\n\tADD\n");
    emit("\tSTA __dq\n\tJNC __dm0\n\tLDA __dq+1\n\tINC\n\tSTA __dq+1\n\tJMP __dm0\n__dm2:\tRTS\n");
    return emit("__dq:   .fill 2\n__dr:   .fill 2\n");
}
int rt_shl() {
    emit("__shl:\tLDA __ax\n\tSTA __sc\n__shl0:\tLDA __sc\n\tJZ __shld\n\tLDA __t0\n\tSHL\n\tSTA __t0\n");
    emit("\tLDA __t0+1\n\tROL\n\tSTA __t0+1\n\tLDA __sc\n\tDEC\n\tSTA __sc\n\tJMP __shl0\n");
    return emit("__shld:\tLDA __t0\n\tSTA __ax\n\tLDA __t0+1\n\tSTA __ax+1\n\tRTS\n");
}
int rt_shr() {
    emit("__shr:\tLDA __ax\n\tSTA __sc\n__shr0:\tLDA __sc\n\tJZ __shrd\n\tLDA __t0+1\n\tSHR\n\tSTA __t0+1\n");
    emit("\tLDA __t0\n\tROR\n\tSTA __t0\n\tLDA __sc\n\tDEC\n\tSTA __sc\n\tJMP __shr0\n");
    return emit("__shrd:\tLDA __t0\n\tSTA __ax\n\tLDA __t0+1\n\tSTA __ax+1\n\tRTS\n");
}
int rt_lnot() {
    emit("__lnot:\tLDA __ax\n\tLDB __ax+1\n\tOR\n\tJZ __ln1\n\tLDA #0\n\tSTA __ax\n\tSTA __ax+1\n\tRTS\n");
    return emit("__ln1:\tLDA #1\n\tSTA __ax\n\tLDA #0\n\tSTA __ax+1\n\tRTS\n");
}
int compile() {
    emit("\t.org $5900\n\tTPA3L\n\tSTA __sp0\n\tTPA3H\n\tSTA __sp0+1\n\tLDB #248\n\tCMP\n\tJNC __sk0\n");
    emit("\tLDP3 #63487\n__sk0:\tJSR _f_main\n\tLPW3 __sp0\n\tRTS\n");
    advance();
    while (curk) { if (bailed) return 0; funcdef(); }
    if (bailed) return 0;
    emit("__cmp:\tLDA __t0+1\n\tLDB __ax+1\n\tCMP\n\tJNZ __cm0\n\tLDA __t0\n\tLDB __ax\n\tCMP\n__cm0:\tRTS\n");
    if (usemul) rt_mul();
    if (usediv) rt_div();
    if (usenot) rt_lnot();
    if (useshl) rt_shl();
    if (useshr) rt_shr();
    emit("__t0:   .fill 2\n__sp0:  .fill 2\n__ax:   .fill 2\n__c:    .fill 1\n__sc:   .fill 1\n__V:   .fill ");
    emitnum(slotcnt + slotcnt);
    return emitnl();
}

/* ---- the argument and the path ---- */
int abspfx() {                           /* apathb = path made absolute (FRESOLVE starts at root) */
    char *s; int n;
    n = 0;
    if (path[0] != '/') {
        bios(SYS_GETCWD, apathb, 0);
        while (apathb[n]) n = n + 1;
        if (apathb[n - 1] != '/') { apathb[n] = '/'; n = n + 1; }
    }
    s = path;
    while (*s) { apathb[n] = *s; n = n + 1; s = s + 1; }
    apathb[n] = 0;
    return 0;
}
int main() {
    char *a; int n; int c; int *h;
    a = argstr();
    c = *a;
    while (c == ' ') { a = a + 1; c = *a; }
    n = 0;
    while (c != 0 && c != ' ' && c != 13) { path[n] = c; n = n + 1; a = a + 1; c = *a; }
    path[n] = 0;
    if (n == 0) { emit("usage: cc src.c >out.asm"); return 0; }
    abspfx();
    bios(FSDIRBUF, 0, DIRPAGE);          /* the directory scan off SBUF: a redirected stream lives there */
    bios(FRESOLVE, apathb, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { emit("cc: cannot open source"); return 0; }
    h = HEADS; n = 0;
    while (n < 224) { h[n] = 0; n = n + 1; }
    arenap = ARENA; larenap = LARENA;
    pbf = 0; usesp = 0; maccnt = 0; fcnt = 0; lblcnt = 0; slotcnt = 0; bailed = 0;
    usemul = 0; usediv = 0; usenot = 0; useshl = 0; useshr = 0;
    condf = 0; conddone = 0; curbrk = 0; curcont = 0;
    compile();
    return 0;
}
