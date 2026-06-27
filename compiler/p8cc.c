/* p8cc.c - the P8X C compiler, written in its own small-C subset.
 *
 * This is the self-hosting rewrite of p8cc.py (Milestone A).  It is BOTH valid
 * standard C and valid p8cc-subset C, so it builds two ways:
 *     gcc p8cc.c -o p8cc_host          # native bootstrap compiler
 *     python3 p8cc.py p8cc.c -o x.asm  # the self-compile proof
 * Source is read from stdin, assembly written to stdout:
 *     ./p8cc_host < prog.c > prog.asm
 *
 * Subset rules obeyed here (so p8cc.py can compile this file): no break/
 * continue, no ++/-- or += , no ?: , no switch, one declaration per statement,
 * for-init is an expression (loop vars declared first), functions defined
 * before use (gcc needs no implicit declarations) with prototypes for mutual
 * recursion, only getchar/putchar/puts for I/O.  EOF is c==0 (P8X CONIN at end
 * of stdin) or c==-1 (host getchar).
 *
 * Built incrementally.  Current language: functions with parameters, stack
 * locals and recursion (a __csp/__fp software frame, args pushed left-to-right
 * so param i is at __fp+2*(pcount-i)); global int variables (optional constant
 * initializer); the FULL expression operator set (precedence ladder + - * / %
 * << >> < > <= >= == != & ^ | && || and unary - ! ~); assignment; putchar(e)
 * and user calls (plus builtins: getchar/putchar/puts over the OS stream
 * syscalls so program I/O is shell-redirectable, peek/poke for byte memory,
 * bios(constaddr,p1,a) to call any monitor routine returning A|carry<<8, and
 * argstr() for the RUN command tail in P2);
 * statements: block, decl, if/else, while, for, return, expr;
 * a char/int type system with pointers (& and *, correct 1/2-byte load/store,
 * pointer arithmetic scaled by element size) via an lvalue-address model;
 * arrays (decl, decay, e[i] indexing), string literals (pooled), the puts
 * builtin, and struct/union types with . and -> member access.  This now spans
 * the whole p8cc.py subset (it self-compiles); only larger inputs await
 * Milestone B (running on the P8X needs streaming, not more language).
 */
#include <stdio.h>

/* ---- token kinds (globals w/ initializers, since the subset has no enum) -- */
int T_EOF = 0;
int T_NUM = 1;
int T_ID = 2;
int T_KW = 3;
int T_STR = 4;
int T_PUNCT = 5;

/* ---- scanner state -------------------------------------------------------- */
char src[32768];     /* whole source, NUL-terminated. Host-side buffer only —
                      * a clib-spliced command (e.g. sed + stdin/glob/regex libs)
                      * is ~17 KB and overflowed the old 16 KB. (Milestone B streams
                      * this on-target, so this size doesn't constrain the target.) */
int srclen = 0;
int spos = 0;        /* scan cursor */
int tok = 0;         /* current token kind */
int tval = 0;        /* numeric value when tok == T_NUM */
char tname[64];      /* identifier / keyword / punctuation text */
char tstr[256];      /* decoded bytes of the last T_STR token */
int tstrlen = 0;

/* ---- small helpers (callee-before-caller, for gcc) ------------------------ */
int streq(char *a, char *b) {
    while (*a != 0) {
        if (*a != *b) return 0;
        a = a + 1;
        b = b + 1;
    }
    return *b == 0;
}

int is_digit(int c) { return c >= 48 && c <= 57; }

int is_alpha(int c) {
    if (c >= 65 && c <= 90) return 1;     /* A-Z */
    if (c >= 97 && c <= 122) return 1;    /* a-z */
    if (c == 95) return 1;                /* _   */
    return 0;
}

int is_alnum(int c) { return is_alpha(c) || is_digit(c); }

int is_hex(int c) {
    if (is_digit(c)) return 1;
    if (c >= 97 && c <= 102) return 1;    /* a-f */
    if (c >= 65 && c <= 70) return 1;     /* A-F */
    return 0;
}

int hexval(int c) {
    if (c <= 57) return c - 48;
    if (c <= 70) return c - 55;           /* A-F */
    return c - 87;                        /* a-f */
}

int is_keyword(char *s) {
    if (streq(s, "int")) return 1;
    if (streq(s, "char")) return 1;
    if (streq(s, "void")) return 1;
    if (streq(s, "struct")) return 1;
    if (streq(s, "union")) return 1;
    if (streq(s, "if")) return 1;
    if (streq(s, "else")) return 1;
    if (streq(s, "while")) return 1;
    if (streq(s, "for")) return 1;
    if (streq(s, "return")) return 1;
    return 0;
}

/* ---- read all of stdin into src[] ----------------------------------------- */
/* Bounded by sizeof(src)-1 so an oversized file truncates safely instead of
 * overflowing the buffer.  (src is a host-side 32 KB buffer; on-target — the
 * open Milestone B — this slurp would become a stream.) */
int slurp() {
    int c;
    int n;
    n = 0;
    c = getchar();
    while (c != 0 && c != -1 && n < 32767) {
        src[n] = c;
        n = n + 1;
        c = getchar();
    }
    src[n] = 0;
    srclen = n;
    return n;
}

/* ---- the lexer: advance one token, set tok/tval/tname --------------------- */
int lex() {
    int c;
    int c2;
    int go;
    int done;
    int n;

    /* skip whitespace, // and slash-star comments, and # preprocessor lines */
    go = 1;
    while (go) {
        c = src[spos];
        if (c == 32 || c == 9 || c == 13 || c == 10) {
            spos = spos + 1;
        } else if (c == 47 && src[spos + 1] == 47) {       /* //  */
            while (src[spos] != 10 && src[spos] != 0) spos = spos + 1;
        } else if (c == 47 && src[spos + 1] == 42) {       /* slash-star */
            spos = spos + 2;
            done = 0;
            while (src[spos] != 0 && done == 0) {
                if (src[spos] == 42 && src[spos + 1] == 47) {
                    spos = spos + 2;
                    done = 1;
                } else {
                    spos = spos + 1;
                }
            }
        } else if (c == 35) {                              /* # line */
            while (src[spos] != 10 && src[spos] != 0) spos = spos + 1;
        } else {
            go = 0;
        }
    }

    c = src[spos];
    if (c == 0) {
        tok = T_EOF;
        return tok;
    }

    /* identifier or keyword */
    if (is_alpha(c)) {
        n = 0;
        while (is_alnum(src[spos])) {
            tname[n] = src[spos];
            n = n + 1;
            spos = spos + 1;
        }
        tname[n] = 0;
        if (is_keyword(tname)) tok = T_KW;
        else tok = T_ID;
        return tok;
    }

    /* number: hex 0x.. or decimal */
    if (is_digit(c)) {
        tval = 0;
        if (c == 48 && (src[spos + 1] == 120 || src[spos + 1] == 88)) {
            spos = spos + 2;
            while (is_hex(src[spos])) {
                tval = tval * 16 + hexval(src[spos]);
                spos = spos + 1;
            }
        } else {
            while (is_digit(src[spos])) {
                tval = tval * 10 + (src[spos] - 48);
                spos = spos + 1;
            }
        }
        tok = T_NUM;
        return tok;
    }

    /* character literal */
    if (c == 39) {                                          /* ' */
        spos = spos + 1;
        if (src[spos] == 92) {                              /* backslash escape */
            spos = spos + 1;
            c = src[spos];
            if (c == 110) tval = 10;                        /* \n */
            else if (c == 116) tval = 9;                    /* \t */
            else if (c == 114) tval = 13;                   /* \r */
            else if (c == 48) tval = 0;                     /* \0 */
            else tval = c;                                  /* \\ \' etc */
            spos = spos + 1;
        } else {
            tval = src[spos];
            spos = spos + 1;
        }
        if (src[spos] == 39) spos = spos + 1;               /* closing ' */
        tok = T_NUM;
        return tok;
    }

    /* string literal: decode escapes into tstr[] */
    if (c == 34) {                                          /* " */
        spos = spos + 1;
        n = 0;
        while (src[spos] != 34 && src[spos] != 0) {
            if (src[spos] == 92) {                          /* backslash escape */
                spos = spos + 1;
                c = src[spos];
                if (c == 110) tstr[n] = 10;
                else if (c == 116) tstr[n] = 9;
                else if (c == 114) tstr[n] = 13;
                else if (c == 48) tstr[n] = 0;
                else tstr[n] = c;
                n = n + 1; spos = spos + 1;
            } else {
                tstr[n] = src[spos]; n = n + 1; spos = spos + 1;
            }
        }
        if (src[spos] == 34) spos = spos + 1;
        tstr[n] = 0; tstrlen = n;
        tok = T_STR;
        return tok;
    }

    /* punctuation: try the two-char operators, then a single char */
    c2 = src[spos + 1];
    if (c2 != 0) {
        done = 0;
        if (c == 61 && c2 == 61) done = 1;                  /* == */
        else if (c == 33 && c2 == 61) done = 1;             /* != */
        else if (c == 60 && c2 == 61) done = 1;             /* <= */
        else if (c == 62 && c2 == 61) done = 1;             /* >= */
        else if (c == 60 && c2 == 60) done = 1;             /* << */
        else if (c == 62 && c2 == 62) done = 1;             /* >> */
        else if (c == 38 && c2 == 38) done = 1;             /* && */
        else if (c == 124 && c2 == 124) done = 1;           /* || */
        else if (c == 45 && c2 == 62) done = 1;             /* -> */
        if (done) {
            tname[0] = c;
            tname[1] = c2;
            tname[2] = 0;
            spos = spos + 2;
            tok = T_PUNCT;
            return tok;
        }
    }
    tname[0] = c;
    tname[1] = 0;
    spos = spos + 1;
    tok = T_PUNCT;
    return tok;
}

/* ---- output helpers ------------------------------------------------------- */
int nlabel = 0;      /* unique-label counter (for && || branches) */
int use_add = 0;
int use_sub = 0;
int use_mul = 0;
int use_div = 0;
int use_mod = 0;
int use_and = 0;
int use_or = 0;
int use_xor = 0;
int use_shl = 0;
int use_shr = 0;
int use_not = 0;
int use_eq = 0;
int use_lt = 0;

int use_enter = 0;
int use_leave = 0;
int use_lea = 0;
int use_push = 0;

/* A type is (base, ptr) packed in one int: base in bit 0 (0=int, 1=char),
   pointer depth in bits 8+.  Expression functions also carry an lvalue flag in
   bit 1 (when set, __ax holds the object's ADDRESS, not its value). */
int g_ptr = 0;       /* pointer depth from the most recent parse_type() */

/* ---- global variable table (single-pass, declared before use) ------------- */
char gpool[1024];    /* packed NUL-terminated names */
int gpooln = 0;
int goff[64];        /* name offset in gpool */
int gbase[64];       /* base type (0 int / 1 char) */
int gptr[64];        /* pointer depth */
int gcnt[64];        /* array element count (0 = scalar) */
int ghas[64];        /* has a constant initializer? */
int gini[64];        /* the initializer value */
int gcount = 0;

/* ---- string-literal pool (emitted as __sN: .byte ... at the end) ---------- */
char spool[1024];
int spooln = 0;
int soff[64];        /* offset of string i in spool */
int slen[64];        /* length of string i */
int scount = 0;

/* ---- per-function scope: params (frame offset +2,+4..) and locals (-2,-4..) */
char vpool[512];     /* packed names of the current function's params+locals */
int vpooln = 0;
int vnoff[64];       /* name offset in vpool */
int vfoff[64];       /* frame offset relative to __fp */
int vbase[64];       /* base type */
int vptr[64];        /* pointer depth */
int vcnt[64];        /* array element count (0 = scalar) */
int vcount = 0;
int nlocoff = 0;     /* running frame offset for locals (grows negative) */
char curfunc[64];    /* name of the function being compiled (for _ret_) */

/* ---- variable lookup result ----------------------------------------------- */
int look_off = 0;        /* frame offset (locals/params) */
int look_base = 0;
int look_ptr = 0;
int look_cnt = 0;        /* array element count (0 = scalar) */
int look_isglobal = 0;

int emitstr(char *s) {
    while (*s != 0) { putchar(*s); s = s + 1; }
    return 0;
}

int line(char *s) { emitstr(s); putchar(10); return 0; }

int emitdec(int v) {                 /* unsigned decimal (values are 0..65535) */
    char buf[6];
    int n;
    if (v == 0) { putchar(48); return 0; }
    n = 0;
    while (v != 0) { buf[n] = 48 + (v % 10); n = n + 1; v = v / 10; }
    while (n != 0) { n = n - 1; putchar(buf[n]); }
    return 0;
}

int strcpy_(char *d, char *s) {
    while (*s != 0) { *d = *s; d = d + 1; s = s + 1; }
    *d = 0;
    return 0;
}

int intern(char *s) {                /* copy a name into gpool, return its offset */
    int off;
    off = gpooln;
    while (*s != 0) { gpool[gpooln] = *s; gpooln = gpooln + 1; s = s + 1; }
    gpool[gpooln] = 0; gpooln = gpooln + 1;
    return off;
}

int addglobal(char *nm, int base, int ptr, int cnt, int hasi, int v) {
    goff[gcount] = intern(nm);
    gbase[gcount] = base;
    gptr[gcount] = ptr;
    gcnt[gcount] = cnt;
    ghas[gcount] = hasi;
    gini[gcount] = v;
    gcount = gcount + 1;
    return 0;
}

int intern_v(char *s) {              /* like intern, but into the per-fn vpool */
    int off;
    off = vpooln;
    while (*s != 0) { vpool[vpooln] = *s; vpooln = vpooln + 1; s = s + 1; }
    vpool[vpooln] = 0; vpooln = vpooln + 1;
    return off;
}

int addvar(char *nm, int foff, int base, int ptr, int cnt) {
    vnoff[vcount] = intern_v(nm);
    vfoff[vcount] = foff;
    vbase[vcount] = base;
    vptr[vcount] = ptr;
    vcnt[vcount] = cnt;
    vcount = vcount + 1;
    return 0;
}

int lookup(char *nm) {               /* 1 if found; sets look_* (local first) */
    int i;
    i = 0;
    while (i < vcount) {
        if (streq(vpool + vnoff[i], nm)) {
            look_off = vfoff[i]; look_base = vbase[i]; look_ptr = vptr[i];
            look_cnt = vcnt[i]; look_isglobal = 0; return 1;
        }
        i = i + 1;
    }
    i = 0;
    while (i < gcount) {
        if (streq(gpool + goff[i], nm)) {
            look_base = gbase[i]; look_ptr = gptr[i]; look_cnt = gcnt[i];
            look_isglobal = 1; return 1;
        }
        i = i + 1;
    }
    return 0;
}

/* ---- struct/union layouts ------------------------------------------------- */
char stpool[512];    /* tag names */
int stpooln = 0;
int stnoff[16];      /* tag name offset */
int stsz[16];        /* total size in bytes */
int stfirst[16];     /* index of first member in the flat member arrays */
int stnm[16];        /* number of members */
int stcount = 0;
char mpool[1024];    /* member names (flat across all structs) */
int mpooln = 0;
int mnoff[160];      /* member name offset */
int moff[160];       /* member offset within its struct */
int mbase[160];      /* member base type */
int mptr[160];       /* member pointer depth */
int mcnt[160];       /* member array count (0 = scalar) */
int mtotal = 0;
int mm_off = 0;      /* find_member result */
int mm_base = 0;
int mm_ptr = 0;
int mm_cnt = 0;

int struct_size(int idx) { return stsz[idx]; }

int find_struct(char *tag) {         /* tag index, or -1 */
    int i;
    i = 0;
    while (i < stcount) { if (streq(stpool + stnoff[i], tag)) return i; i = i + 1; }
    return 0 - 1;
}

int find_member(int sidx, char *nm) {/* sets mm_*; 1 if found */
    int i;
    int e;
    i = stfirst[sidx];
    e = stfirst[sidx] + stnm[sidx];
    while (i < e) {
        if (streq(mpool + mnoff[i], nm)) {
            mm_off = moff[i]; mm_base = mbase[i]; mm_ptr = mptr[i]; mm_cnt = mcnt[i];
            return 1;
        }
        i = i + 1;
    }
    return 0;
}

/* base: 0=int, 1=char, 2+idx = struct/union tag #idx */
int type_size(int base, int ptr) {   /* bytes of one object of this type */
    if (ptr > 0) return 2;
    if (base == 1) return 1;
    if (base >= 2) return struct_size(base - 2);
    return 2;
}

/* ---- type encoding: (base, ptr, lval) packed in one int ------------------- */
int mkty(int base, int ptr, int lv) { return base + lv * 256 + ptr * 512; }
int ty_base(int ty) { return ty & 255; }
int ty_lval(int ty) { return (ty >> 8) & 1; }
int ty_ptr(int ty) { return ty >> 9; }
int ty_size(int ty) {                /* bytes of the value */
    if (ty_ptr(ty) > 0) return 2;
    return type_size(ty_base(ty), 0);
}
int elem_size(int ty) {              /* size of *ty (one level less indirection) */
    if (ty_ptr(ty) > 1) return 2;
    return type_size(ty_base(ty), 0);
}

int is_punct(char *p) { return tok == T_PUNCT && streq(tname, p); }

int eat(char *p) {
    if (is_punct(p) == 0) { emitstr("; ERROR: expected "); line(p); }
    lex();
    return 0;
}

/* ---- codegen primitives (an expression's result lives in __ax) ------------ */
int set_ax(int v) {                  /* __ax = constant v */
    emitstr("        LDA #"); emitdec(v & 255); putchar(10);
    line("        STA __ax");
    emitstr("        LDA #"); emitdec((v >> 8) & 255); putchar(10);
    line("        STA __ax+1");
    return 0;
}

int push_ax() {                      /* push __ax onto the P3 hardware stack */
    line("        PHW __ax");         /* 16-bit push (was LDA/PHA/LDA/PHA) */
    return 0;
}

int pop_t() {                        /* pop into __t */
    line("        PLW __t");          /* 16-bit pop (was PLA/STA/PLA/STA) */
    return 0;
}

int swap_tax() {                     /* exchange __t and __ax (for > and <=) */
    line("        LDA __t"); line("        PHA");
    line("        LDA __t+1"); line("        PHA");
    line("        LDA __ax"); line("        STA __t");
    line("        LDA __ax+1"); line("        STA __t+1");
    line("        PLA"); line("        STA __ax+1");
    line("        PLA"); line("        STA __ax");
    return 0;
}

int lea_off(int off) {               /* P1 = __fp + off (offset inline after JSR) */
    line("        JSR __lea"); use_lea = 1;
    emitstr("        .word "); emitdec(off & 0xFFFF); putchar(10);
    return 0;
}

int load_local(int off) {            /* __ax = *(fp+off) */
    lea_off(off);
    line("        LDA (P1)+"); line("        STA __ax");
    line("        LDA (P1)"); line("        STA __ax+1");
    return 0;
}

int store_local(int off, int sz) {   /* *(fp+off) = __ax by width (__ax preserved) */
    lea_off(off);
    if (sz == 2) {
        line("        LDA __ax"); line("        STA (P1)+");
        line("        LDA __ax+1"); line("        STA (P1)");
    } else {
        line("        LDA __ax"); line("        STA (P1)");
    }
    return 0;
}

/* emit a label like "Lname<n>:" and remember n via the caller's variable */
int emitlabel(char *base, int n) {
    emitstr(base); emitdec(n); putchar(58); putchar(10);   /* ':' = 58 */
    return 0;
}
int emitjmp(char *op, char *base, int n) {                 /* op base<n> */
    emitstr("        "); emitstr(op); putchar(32);
    emitstr(base); emitdec(n); putchar(10);
    return 0;
}

int test_jz(char *base, int n) {     /* if __ax == 0 jump to base<n> */
    line("        LDA __ax"); line("        LDB __ax+1"); line("        OR");
    emitjmp("JZ", base, n);
    return 0;
}

int addconst_ax(int kk) {            /* __ax += kk (16-bit constant) */
    int k;
    if (kk == 0) return 0;
    k = nlabel; nlabel = nlabel + 1;
    line("        LDA __ax");
    emitstr("        LDB #"); emitdec(kk & 255); putchar(10);
    line("        ADD"); line("        STA __ax");
    line("        LDA #0"); emitjmp("JNC", "Lac", k); line("        LDA #1");
    emitlabel("Lac", k); line("        STA __c");
    line("        LDA __ax+1");
    emitstr("        LDB #"); emitdec((kk >> 8) & 255); putchar(10);
    line("        ADD"); line("        LDB __c"); line("        ADD");
    line("        STA __ax+1");
    return 0;
}

/* ---- runtime helpers (emitted only if used) ------------------------------- */
int emit_add() {
    line("__add:  LDA __t");    line("        LDB __ax");  line("        ADD");
    line("        STA __ax");   line("        LDA #0");    line("        JNC __add1");
    line("        LDA #1");     line("__add1: STA __c");   line("        LDA __t+1");
    line("        LDB __ax+1"); line("        ADD");       line("        LDB __c");
    line("        ADD");        line("        STA __ax+1");line("        RTS");
    return 0;
}
int emit_sub() {
    line("__sub:  LDA __t");    line("        LDB __ax");  line("        SUB");
    line("        STA __ax");   line("        LDA #0");    line("        JC __sub1");
    line("        LDA #1");     line("__sub1: STA __c");   line("        LDA __t+1");
    line("        LDB __ax+1"); line("        SUB");       line("        STA __ax+1");
    line("        LDA __c");    line("        JZ __sub2"); line("        LDA __ax+1");
    line("        LDB #1");     line("        SUB");       line("        STA __ax+1");
    line("__sub2: RTS");
    return 0;
}
int emit_mul() {
    line("__mul:  LDA #0");     line("        STA __r");   line("        STA __r+1");
    line("        LDA #16");    line("        STA __n");
    line("__mul_l: LDA __ax");  line("        LDB #1");    line("        AND");
    line("        JZ __mul_s");
    line("        LDA __r");    line("        LDB __t");   line("        ADD");
    line("        STA __r");    line("        LDA #0");    line("        JNC __mul_a");
    line("        LDA #1");     line("__mul_a: STA __c");  line("        LDA __r+1");
    line("        LDB __t+1");  line("        ADD");       line("        LDB __c");
    line("        ADD");        line("        STA __r+1");
    line("__mul_s: LDA __t");   line("        SHL");       line("        STA __t");
    line("        LDA __t+1");  line("        ROL");       line("        STA __t+1");
    line("        LDA __ax+1"); line("        SHR");       line("        STA __ax+1");
    line("        LDA __ax");   line("        ROR");       line("        STA __ax");
    line("        LDA __n");    line("        DEC");       line("        STA __n");
    line("        JNZ __mul_l");
    line("        LDA __r");    line("        STA __ax");
    line("        LDA __r+1");  line("        STA __ax+1");line("        RTS");
    return 0;
}
int emit_divmod() {
    line("__divmod: LDA #0");   line("        STA __dr");  line("        STA __dr+1");
    line("        LDA #16");    line("        STA __n");
    line("__dm_l: LDA __t");    line("        SHL");       line("        STA __t");
    line("        LDA __t+1");  line("        ROL");       line("        STA __t+1");
    line("        LDA __dr");   line("        ROL");       line("        STA __dr");
    line("        LDA __dr+1"); line("        ROL");       line("        STA __dr+1");
    line("        LDA __dr+1"); line("        LDB __ax+1");line("        CMP");
    line("        JZ __dm_lo"); line("        JC __dm_ge");line("        JMP __dm_no");
    line("__dm_lo: LDA __dr");  line("        LDB __ax");  line("        CMP");
    line("        JNC __dm_no");
    line("__dm_ge: LDA __dr");  line("        LDB __ax");  line("        SUB");
    line("        STA __dr");   line("        LDA #0");    line("        JC __dm_b");
    line("        LDA #1");     line("__dm_b: STA __c");   line("        LDA __dr+1");
    line("        LDB __ax+1"); line("        SUB");       line("        LDB __c");
    line("        SUB");        line("        STA __dr+1");
    line("        LDA __t");    line("        LDB #1");    line("        OR");
    line("        STA __t");
    line("__dm_no: LDA __n");   line("        DEC");       line("        STA __n");
    line("        JNZ __dm_l"); line("        RTS");
    return 0;
}
int emit_div() {
    line("__div:  JSR __divmod");line("        LDA __t");  line("        STA __ax");
    line("        LDA __t+1");  line("        STA __ax+1");line("        RTS");
    return 0;
}
int emit_mod() {
    line("__mod:  JSR __divmod");line("        LDA __dr"); line("        STA __ax");
    line("        LDA __dr+1"); line("        STA __ax+1");line("        RTS");
    return 0;
}
int emit_and() {
    line("__and:  LDA __t");    line("        LDB __ax");  line("        AND");
    line("        STA __ax");   line("        LDA __t+1"); line("        LDB __ax+1");
    line("        AND");        line("        STA __ax+1");line("        RTS");
    return 0;
}
int emit_or() {
    line("__or:   LDA __t");    line("        LDB __ax");  line("        OR");
    line("        STA __ax");   line("        LDA __t+1"); line("        LDB __ax+1");
    line("        OR");         line("        STA __ax+1");line("        RTS");
    return 0;
}
int emit_xor() {
    line("__xor:  LDA __t");    line("        LDB __ax");  line("        XOR");
    line("        STA __ax");   line("        LDA __t+1"); line("        LDB __ax+1");
    line("        XOR");        line("        STA __ax+1");line("        RTS");
    return 0;
}
int emit_shl() {
    line("__shl:  LDA __ax");   line("        STA __n");   line("        LDA __t");
    line("        STA __ax");   line("        LDA __t+1"); line("        STA __ax+1");
    line("__shl_l: LDA __n");   line("        JZ __shl_e");
    line("        LDA __ax");   line("        SHL");       line("        STA __ax");
    line("        LDA __ax+1"); line("        ROL");       line("        STA __ax+1");
    line("        LDA __n");    line("        DEC");       line("        STA __n");
    line("        JMP __shl_l");line("__shl_e: RTS");
    return 0;
}
int emit_shr() {
    line("__shr:  LDA __ax");   line("        STA __n");   line("        LDA __t");
    line("        STA __ax");   line("        LDA __t+1"); line("        STA __ax+1");
    line("__shr_l: LDA __n");   line("        JZ __shr_e");
    line("        LDA __ax+1"); line("        SHR");       line("        STA __ax+1");
    line("        LDA __ax");   line("        ROR");       line("        STA __ax");
    line("        LDA __n");    line("        DEC");       line("        STA __n");
    line("        JMP __shr_l");line("__shr_e: RTS");
    return 0;
}
int emit_not() {
    line("__not:  LDA __ax");   line("        LDB __ax+1");line("        OR");
    line("        JZ __not1");  line("        LDA #0");    line("        JMP __nots");
    line("__not1: LDA #1");     line("__nots: STA __ax");  line("        LDA #0");
    line("        STA __ax+1"); line("        RTS");
    return 0;
}
int emit_eq() {
    line("__eq:   LDA __t");    line("        LDB __ax");  line("        CMP");
    line("        JNZ __eq0");  line("        LDA __t+1"); line("        LDB __ax+1");
    line("        CMP");        line("        JNZ __eq0"); line("        LDA #1");
    line("        JMP __eqs");  line("__eq0:  LDA #0");    line("__eqs:  STA __ax");
    line("        LDA #0");     line("        STA __ax+1");line("        RTS");
    return 0;
}
int emit_lt() {
    line("__lt:   LDA __t+1");  line("        LDB __ax+1");line("        CMP");
    line("        JZ __lt_lo"); line("        JC __lt0");  line("        JMP __lt1");
    line("__lt_lo: LDA __t");   line("        LDB __ax");  line("        CMP");
    line("        JC __lt0");
    line("__lt1:  LDA #1");     line("        JMP __lts");
    line("__lt0:  LDA #0");     line("__lts:  STA __ax");  line("        LDA #0");
    line("        STA __ax+1"); line("        RTS");
    return 0;
}

int emit_push() {
    line("__push: LDA __csp");  line("        LDB #2");    line("        SUB");
    line("        STA __csp");  line("        JC __pu1");  line("        LDA __csp+1");
    line("        LDB #1");     line("        SUB");       line("        STA __csp+1");
    line("__pu1:  LDA __csp");  line("        TAP1L");     line("        LDA __csp+1");
    line("        TAP1H");      line("        LDA __ax");  line("        STA (P1)+");
    line("        LDA __ax+1"); line("        STA (P1)");  line("        RTS");
    return 0;
}
int emit_enter() {
    line("__enter: LDA __csp"); line("        LDB #2");    line("        SUB");
    line("        STA __csp");  line("        JC __en1");  line("        LDA __csp+1");
    line("        LDB #1");     line("        SUB");       line("        STA __csp+1");
    line("__en1:  LDA __csp");  line("        TAP1L");     line("        LDA __csp+1");
    line("        TAP1H");      line("        LDA __fp");  line("        STA (P1)+");
    line("        LDA __fp+1"); line("        STA (P1)");  line("        LDA __csp");
    line("        STA __fp");   line("        LDA __csp+1");line("        STA __fp+1");
    line("        RTS");
    return 0;
}
int emit_leave() {
    line("__leave: LDA __fp");  line("        STA __csp"); line("        LDA __fp+1");
    line("        STA __csp+1");line("        LDA __csp"); line("        TAP1L");
    line("        LDA __csp+1");line("        TAP1H");     line("        LDA (P1)+");
    line("        STA __fp");   line("        LDA (P1)");  line("        STA __fp+1");
    line("        LDA __csp");  line("        LDB #2");    line("        ADD");
    line("        STA __csp");  line("        JNC __lv1"); line("        LDA __csp+1");
    line("        INC");        line("        STA __csp+1");line("__lv1:  RTS");
    return 0;
}
int emit_lea() {                     /* P1 = __fp + (inline .word offset after the JSR) */
    line("__lea:  PLA");        line("        TAP1L");      line("        PLA");
    line("        TAP1H");                                  /* P1 = return PC -> the .word */
    line("        LDA (P1)+");   line("        STA __off");
    line("        LDA (P1)+");   line("        STA __off+1");/* P1 = retPC+2 */
    line("        TPA1L");       line("        STA __ra");
    line("        TPA1H");       line("        STA __ra+1"); /* save retPC+2 (P1 gets reused) */
    line("        LDA __fp");    line("        LDB __off");  line("        ADD");
    line("        STA __t");     line("        LDA #0");     line("        JNC __la1");
    line("        LDA #1");      line("__la1:  STA __c");    line("        LDA __fp+1");
    line("        LDB __off+1"); line("        ADD");        line("        LDB __c");
    line("        ADD");         line("        STA __t+1");  line("        LDA __t");
    line("        TAP1L");       line("        LDA __t+1");  line("        TAP1H");
    line("        LDA __ra+1");  line("        PHA");        /* push retPC+2 back */
    line("        LDA __ra");    line("        PHA");
    line("        RTS");
    return 0;
}

/* ---- lvalue / type-aware codegen primitives ------------------------------- */
int deref_load(int sz) {             /* __ax holds an address -> load value */
    line("        LDA __ax"); line("        TAP1L");
    line("        LDA __ax+1"); line("        TAP1H");
    if (sz == 2) {
        line("        LDA (P1)+"); line("        STA __ax");
        line("        LDA (P1)"); line("        STA __ax+1");
    } else {
        line("        LDA (P1)"); line("        STA __ax");
        line("        LDA #0"); line("        STA __ax+1");
    }
    return 0;
}

int store_ind(int sz) {              /* __t = address, __ax = value -> store */
    line("        LDA __t"); line("        TAP1L");
    line("        LDA __t+1"); line("        TAP1H");
    if (sz == 2) {
        line("        LDA __ax"); line("        STA (P1)+");
        line("        LDA __ax+1"); line("        STA (P1)");
    } else {
        line("        LDA __ax"); line("        STA (P1)");
    }
    return 0;
}

int rvalue(int ty) {                 /* if __ax holds an lvalue address, load it */
    if (ty_lval(ty)) { deref_load(ty_size(ty)); return mkty(ty_base(ty), ty_ptr(ty), 0); }
    return ty;
}

int scale2_ax() {                    /* __ax <<= 1 (pointer-arith element *2) */
    line("        LDA __ax"); line("        SHL"); line("        STA __ax");
    line("        LDA __ax+1"); line("        ROL"); line("        STA __ax+1");
    return 0;
}
int scale2_t() {                     /* __t <<= 1 */
    line("        LDA __t"); line("        SHL"); line("        STA __t");
    line("        LDA __t+1"); line("        ROL"); line("        STA __t+1");
    return 0;
}

int parse_type() {                   /* tok at a type kw -> base; sets g_ptr */
    int base;
    if (streq(tname, "struct") || streq(tname, "union")) {
        lex();                       /* 'struct' / 'union' */
        base = 2 + find_struct(tname);
        lex();                       /* tag */
    } else {
        base = 0;
        if (streq(tname, "char")) base = 1;
        lex();
    }
    g_ptr = 0;
    while (is_punct("*")) { g_ptr = g_ptr + 1; lex(); }
    return base;
}

/* ---- the precedence ladder (mutually recursive -> forward decls) ----------
   Each function returns the type of what it produced; a bare lvalue carries its
   ADDRESS in __ax (lval bit set) and is dereferenced by rvalue() on demand. */
int expr();
int stmt();

int factor() {
    char nm[64];
    int nargs;
    int k;
    int ty;
    int j;
    int esz;
    int addr;
    ty = mkty(0, 0, 0);
    if (tok == T_NUM) { set_ax(tval); lex(); ty = mkty(0, 0, 0); }
    else if (tok == T_STR) {                     /* string literal -> char* */
        k = scount; scount = scount + 1;
        soff[k] = spooln; slen[k] = tstrlen;
        j = 0;
        while (j < tstrlen) { spool[spooln] = tstr[j]; spooln = spooln + 1; j = j + 1; }
        emitstr("        LDA #<__s"); emitdec(k); putchar(10); line("        STA __ax");
        emitstr("        LDA #>__s"); emitdec(k); putchar(10); line("        STA __ax+1");
        lex();
        ty = mkty(1, 1, 0);
    }
    else if (is_punct("(")) { lex(); ty = expr(); eat(")"); }
    else if (tok == T_ID) {
        strcpy_(nm, tname); lex();
        if (is_punct("(")) {                     /* call / builtin -> int rvalue */
            lex();                               /* '(' */
            if (streq(nm, "getchar")) {          /* OS SYS_GETC -> char, -1 at EOF */
                eat(")");
                line("        JSR $400C"); line("        STA __ax");
                line("        LDA #0"); line("        STA __ax+1");
                k = nlabel; nlabel = nlabel + 1;
                emitjmp("JNC", "Lge", k);        /* carry = end of (file) input */
                line("        LDA #255"); line("        STA __ax"); line("        STA __ax+1");
                emitlabel("Lge", k);             /* __ax = $FFFF (-1) */
            } else if (streq(nm, "putchar")) {   /* OS SYS_PUTC (redirectable) */
                rvalue(expr()); eat(")");
                line("        LDA __ax"); line("        JSR $4009");
            } else if (streq(nm, "puts")) {      /* OS SYS_PUTS + newline */
                rvalue(expr()); eat(")");
                line("        LDA __ax"); line("        TAP1L");
                line("        LDA __ax+1"); line("        TAP1H");
                line("        JSR $400F"); line("        LDA #10"); line("        JSR $4009");
            } else if (streq(nm, "peek")) {      /* peek(addr) -> byte */
                rvalue(expr()); eat(")");
                line("        LDA __ax"); line("        TAP1L");
                line("        LDA __ax+1"); line("        TAP1H");
                line("        LDA (P1)"); line("        STA __ax");
                line("        LDA #0"); line("        STA __ax+1");
            } else if (streq(nm, "poke")) {      /* poke(addr, val) */
                rvalue(expr()); push_ax();
                eat(","); rvalue(expr()); eat(")");
                pop_t();                          /* __t = addr, __ax = val */
                line("        LDA __t"); line("        TAP1L");
                line("        LDA __t+1"); line("        TAP1H");
                line("        LDA __ax"); line("        STA (P1)");
            } else if (streq(nm, "argstr")) {    /* P2 (program arg tail) -> char* */
                eat(")");
                line("        TPA2L"); line("        STA __ax");
                line("        TPA2H"); line("        STA __ax+1");
            } else if (streq(nm, "bios")) {      /* bios(constaddr, p1, a) -> A|carry<<8 */
                if (tok != T_NUM) line("; ERROR: bios addr not constant");
                addr = tval; lex();
                eat(","); rvalue(expr()); push_ax();   /* P1 operand */
                eat(","); rvalue(expr()); eat(")");    /* A operand -> __ax */
                pop_t();                               /* __t = P1 operand */
                line("        LDA __t"); line("        TAP1L");
                line("        LDA __t+1"); line("        TAP1H");
                line("        LDA __ax");
                emitstr("        JSR "); emitdec(addr); putchar(10);
                line("        STA __ax"); line("        LDA #0");   /* returned A -> low */
                k = nlabel; nlabel = nlabel + 1;
                emitjmp("JNC", "Lbc", k); line("        LDA #1"); emitlabel("Lbc", k);
                line("        STA __ax+1");             /* carry -> bit 8 */
            } else {                             /* user function */
                nargs = 0;
                if (is_punct(")") == 0) {
                    rvalue(expr());
                    line("        JSR __push"); use_push = 1; nargs = 1;
                    while (is_punct(",")) {
                        lex(); rvalue(expr());
                        line("        JSR __push"); use_push = 1;
                        nargs = nargs + 1;
                    }
                }
                eat(")");
                emitstr("        JSR _f_"); emitstr(nm); putchar(10);
                if (nargs > 0) {                 /* caller pops args: __csp += 2n */
                    k = nlabel; nlabel = nlabel + 1;
                    line("        LDA __csp");
                    emitstr("        LDB #"); emitdec(2 * nargs); putchar(10);
                    line("        ADD"); line("        STA __csp");
                    emitjmp("JNC", "Lcl", k);
                    line("        LDA __csp+1"); line("        INC"); line("        STA __csp+1");
                    emitlabel("Lcl", k);
                }
            }
            ty = mkty(0, 0, 0);
        } else if (lookup(nm) == 0) {
            line("; ERROR: undeclared id"); ty = mkty(0, 0, 0);
        } else {
            if (look_isglobal) {                 /* address of the variable */
                emitstr("        LDA #<_g_"); emitstr(nm); putchar(10); line("        STA __ax");
                emitstr("        LDA #>_g_"); emitstr(nm); putchar(10); line("        STA __ax+1");
            } else {
                lea_off(look_off);
                line("        TPA1L"); line("        STA __ax");
                line("        TPA1H"); line("        STA __ax+1");
            }
            if (look_cnt > 0) ty = mkty(look_base, look_ptr + 1, 0);  /* array decays */
            else ty = mkty(look_base, look_ptr, 1);                   /* scalar lvalue */
        }
    } else {
        line("; ERROR: bad factor");
    }

    while (is_punct("[") || is_punct(".") || is_punct("->")) {
        if (is_punct("[")) {                      /* e[i] -> *(e + i) lvalue */
            lex();
            ty = rvalue(ty);                      /* pointer value in __ax */
            push_ax();
            rvalue(expr());                       /* index in __ax */
            eat("]");
            esz = elem_size(ty);
            if (esz == 2) scale2_ax();
            pop_t();                              /* __t = base pointer */
            line("        JSR __add"); use_add = 1;
            ty = mkty(ty_base(ty), ty_ptr(ty) - 1, 1);
        } else if (is_punct(".")) {               /* x.m : address of x + offset */
            lex();
            find_member(ty_base(ty) - 2, tname); lex();
            addconst_ax(mm_off);
            if (mm_cnt > 0) ty = mkty(mm_base, mm_ptr + 1, 0);
            else ty = mkty(mm_base, mm_ptr, 1);
        } else {                                  /* p->m : *p + offset */
            lex();
            ty = rvalue(ty);                      /* struct address in __ax */
            find_member(ty_base(ty) - 2, tname); lex();
            addconst_ax(mm_off);
            if (mm_cnt > 0) ty = mkty(mm_base, mm_ptr + 1, 0);
            else ty = mkty(mm_base, mm_ptr, 1);
        }
    }
    return ty;
}

int unary() {
    int ty;
    if (is_punct("&")) {                          /* &lvalue: address already in __ax */
        lex(); ty = unary();
        return mkty(ty_base(ty), ty_ptr(ty) + 1, 0);
    }
    if (is_punct("*")) {                          /* *ptr: lvalue at the pointer value */
        lex(); ty = rvalue(unary());
        return mkty(ty_base(ty), ty_ptr(ty) - 1, 1);
    }
    if (is_punct("-")) {
        lex(); rvalue(unary());
        line("        LDA #0"); line("        STA __t"); line("        STA __t+1");
        line("        JSR __sub"); use_sub = 1;
        return mkty(0, 0, 0);
    }
    if (is_punct("!")) {
        lex(); rvalue(unary());
        line("        JSR __not"); use_not = 1;
        return mkty(0, 0, 0);
    }
    if (is_punct("~")) {
        lex(); rvalue(unary());
        line("        LDA #255"); line("        LDB __ax"); line("        SUB");
        line("        STA __ax"); line("        LDA #255"); line("        LDB __ax+1");
        line("        SUB"); line("        STA __ax+1");
        return mkty(0, 0, 0);
    }
    return factor();
}

int muldiv() {
    int op;
    int ty;
    ty = unary();
    while (is_punct("*") || is_punct("/") || is_punct("%")) {
        op = tname[0];
        lex();
        rvalue(ty); push_ax();
        rvalue(unary()); pop_t();
        if (op == 42) { line("        JSR __mul"); use_mul = 1; }
        else if (op == 47) { line("        JSR __div"); use_div = 1; }
        else { line("        JSR __mod"); use_mod = 1; }
        ty = mkty(0, 0, 0);
    }
    return ty;
}

int addsub() {
    int op;
    int lty;
    int rty;
    lty = muldiv();
    while (is_punct("+") || is_punct("-")) {
        op = tname[0];
        lex();
        lty = rvalue(lty); push_ax();
        rty = rvalue(muldiv()); pop_t();          /* __t = lhs, __ax = rhs */
        if (ty_ptr(lty) > 0 && ty_ptr(rty) == 0) {        /* ptr +/- int */
            if (elem_size(lty) == 2) scale2_ax();
        } else if (op == 43 && ty_ptr(rty) > 0 && ty_ptr(lty) == 0) {  /* int + ptr */
            if (elem_size(rty) == 2) scale2_t();
            lty = rty;
        } else {
            lty = mkty(0, 0, 0);
        }
        if (op == 43) { line("        JSR __add"); use_add = 1; }
        else { line("        JSR __sub"); use_sub = 1; }
    }
    return lty;
}

int shift() {
    char op[3];
    int ty;
    ty = addsub();
    while (is_punct("<<") || is_punct(">>")) {
        strcpy_(op, tname);
        lex();
        rvalue(ty); push_ax();
        rvalue(addsub()); pop_t();
        if (streq(op, "<<")) { line("        JSR __shl"); use_shl = 1; }
        else { line("        JSR __shr"); use_shr = 1; }
        ty = mkty(0, 0, 0);
    }
    return ty;
}

int relational() {
    char op[3];
    int ty;
    ty = shift();
    while (is_punct("<") || is_punct(">") || is_punct("<=") || is_punct(">=")) {
        strcpy_(op, tname);
        lex();
        rvalue(ty); push_ax();
        rvalue(shift()); pop_t();
        if (streq(op, ">") || streq(op, "<=")) swap_tax();
        line("        JSR __lt"); use_lt = 1;
        if (streq(op, "<=") || streq(op, ">=")) { line("        JSR __not"); use_not = 1; }
        ty = mkty(0, 0, 0);
    }
    return ty;
}

int equality() {
    char op[3];
    int ty;
    ty = relational();
    while (is_punct("==") || is_punct("!=")) {
        strcpy_(op, tname);
        lex();
        rvalue(ty); push_ax();
        rvalue(relational()); pop_t();
        line("        JSR __eq"); use_eq = 1;
        if (streq(op, "!=")) { line("        JSR __not"); use_not = 1; }
        ty = mkty(0, 0, 0);
    }
    return ty;
}

int bitand_() {
    int ty;
    ty = equality();
    while (is_punct("&")) {
        lex();
        rvalue(ty); push_ax();
        rvalue(equality()); pop_t();
        line("        JSR __and"); use_and = 1;
        ty = mkty(0, 0, 0);
    }
    return ty;
}

int bitxor_() {
    int ty;
    ty = bitand_();
    while (is_punct("^")) {
        lex();
        rvalue(ty); push_ax();
        rvalue(bitand_()); pop_t();
        line("        JSR __xor"); use_xor = 1;
        ty = mkty(0, 0, 0);
    }
    return ty;
}

int bitor_() {
    int ty;
    ty = bitxor_();
    while (is_punct("|")) {
        lex();
        rvalue(ty); push_ax();
        rvalue(bitxor_()); pop_t();
        line("        JSR __or"); use_or = 1;
        ty = mkty(0, 0, 0);
    }
    return ty;
}

int logand() {
    int f;
    int e;
    int ty;
    ty = bitor_();
    while (is_punct("&&")) {
        f = nlabel; nlabel = nlabel + 1;
        e = nlabel; nlabel = nlabel + 1;
        lex();
        rvalue(ty);
        line("        LDA __ax"); line("        LDB __ax+1"); line("        OR");
        emitjmp("JZ", "Land", f);
        rvalue(bitor_());
        line("        LDA __ax"); line("        LDB __ax+1"); line("        OR");
        emitjmp("JZ", "Land", f);
        line("        LDA #1"); line("        STA __ax"); line("        LDA #0");
        line("        STA __ax+1");
        emitjmp("JMP", "Lande", e);
        emitlabel("Land", f);
        line("        LDA #0"); line("        STA __ax"); line("        STA __ax+1");
        emitlabel("Lande", e);
        ty = mkty(0, 0, 0);
    }
    return ty;
}

int logor() {
    int t;
    int e;
    int ty;
    ty = logand();
    while (is_punct("||")) {
        t = nlabel; nlabel = nlabel + 1;
        e = nlabel; nlabel = nlabel + 1;
        lex();
        rvalue(ty);
        line("        LDA __ax"); line("        LDB __ax+1"); line("        OR");
        emitjmp("JNZ", "Lor", t);
        rvalue(logand());
        line("        LDA __ax"); line("        LDB __ax+1"); line("        OR");
        emitjmp("JNZ", "Lor", t);
        line("        LDA #0"); line("        STA __ax"); line("        STA __ax+1");
        emitjmp("JMP", "Lore", e);
        emitlabel("Lor", t);
        line("        LDA #1"); line("        STA __ax"); line("        LDA #0");
        line("        STA __ax+1");
        emitlabel("Lore", e);
        ty = mkty(0, 0, 0);
    }
    return ty;
}

int expr() {                          /* assignment (right-associative) */
    int lty;
    int rty;
    lty = logor();
    if (is_punct("=")) {
        push_ax();                    /* save the lvalue address */
        lex();
        rty = rvalue(expr());         /* value in __ax */
        pop_t();                      /* __t = address */
        store_ind(ty_size(lty));
        return mkty(ty_base(lty), ty_ptr(lty), 0);
    }
    return lty;
}

/* ---- statements ----------------------------------------------------------- */
int block() {
    eat("{");
    while (is_punct("}") == 0 && tok != T_EOF) stmt();
    eat("}");
    return 0;
}

int stmt() {
    int l1;
    int l2;
    int l3;
    int l4;
    if (is_punct("{")) { block(); return 0; }
    if (tok == T_KW && (streq(tname, "int") || streq(tname, "char")
                        || streq(tname, "struct") || streq(tname, "union"))) {
        char dn[64];
        int off;
        int base;
        int cnt;
        int sz;
        base = parse_type();                      /* type + '*'s -> base, g_ptr */
        strcpy_(dn, tname); lex();                /* name */
        cnt = 0;
        if (is_punct("[")) { lex(); cnt = tval; lex(); eat("]"); }
        if (cnt > 0) sz = cnt * type_size(base, g_ptr);
        else sz = type_size(base, g_ptr);
        nlocoff = nlocoff - sz;
        off = nlocoff;
        addvar(dn, off, base, g_ptr, cnt);
        if (cnt == 0 && is_punct("=")) {
            lex(); rvalue(expr()); store_local(off, type_size(base, g_ptr));
        }
        eat(";");
        return 0;
    }
    if (tok == T_KW && streq(tname, "return")) {
        lex();
        if (is_punct(";") == 0) rvalue(expr());
        eat(";");
        emitstr("        JMP _ret_"); emitstr(curfunc); putchar(10);
        return 0;
    }
    if (tok == T_KW && streq(tname, "if")) {
        lex(); eat("("); rvalue(expr()); eat(")");
        l1 = nlabel; nlabel = nlabel + 1;
        l2 = nlabel; nlabel = nlabel + 1;
        test_jz("Lif", l1);                       /* false -> else/end */
        stmt();
        if (tok == T_KW && streq(tname, "else")) {
            emitjmp("JMP", "Lif", l2);
            emitlabel("Lif", l1);
            lex();
            stmt();
            emitlabel("Lif", l2);
        } else {
            emitlabel("Lif", l1);
        }
        return 0;
    }
    if (tok == T_KW && streq(tname, "while")) {
        l1 = nlabel; nlabel = nlabel + 1;         /* top */
        l2 = nlabel; nlabel = nlabel + 1;         /* end */
        lex();
        emitlabel("Lw", l1);
        eat("("); rvalue(expr()); eat(")");
        test_jz("Lw", l2);
        stmt();
        emitjmp("JMP", "Lw", l1);
        emitlabel("Lw", l2);
        return 0;
    }
    if (tok == T_KW && streq(tname, "for")) {
        /* layout: init; top: cond?JZ end; JMP body; post: post; JMP top;
           body: BODY; JMP post; end:   (emits post before body, runtime loops) */
        lex(); eat("(");
        if (is_punct(";") == 0) expr();
        eat(";");
        l1 = nlabel; nlabel = nlabel + 1;         /* top  */
        l2 = nlabel; nlabel = nlabel + 1;         /* post */
        l3 = nlabel; nlabel = nlabel + 1;         /* body */
        l4 = nlabel; nlabel = nlabel + 1;         /* end  */
        emitlabel("Lf", l1);
        if (is_punct(";") == 0) { rvalue(expr()); test_jz("Lf", l4); }
        eat(";");
        emitjmp("JMP", "Lf", l3);
        emitlabel("Lf", l2);
        if (is_punct(")") == 0) expr();
        eat(")");
        emitjmp("JMP", "Lf", l1);
        emitlabel("Lf", l3);
        stmt();
        emitjmp("JMP", "Lf", l2);
        emitlabel("Lf", l4);
        return 0;
    }
    if (is_punct(";")) { lex(); return 0; }
    expr();
    eat(";");
    return 0;
}

/* ---- emit all used runtime helpers + the data section --------------------- */
int emit_runtime() {
    if (use_enter) emit_enter();
    if (use_leave) emit_leave();
    if (use_push) emit_push();
    if (use_lea) emit_lea();
    if (use_add) emit_add();
    if (use_sub) emit_sub();
    if (use_mul) emit_mul();
    if (use_div || use_mod) emit_divmod();
    if (use_div) emit_div();
    if (use_mod) emit_mod();
    if (use_and) emit_and();
    if (use_or) emit_or();
    if (use_xor) emit_xor();
    if (use_shl) emit_shl();
    if (use_shr) emit_shr();
    if (use_not) emit_not();
    if (use_eq) emit_eq();
    if (use_lt) emit_lt();
    line("__ax:   .fill 2");
    line("__t:    .fill 2");
    line("__c:    .fill 1");
    line("__fp:   .fill 2");
    line("__off:  .fill 2");
    line("__ra:   .fill 2");
    line("__csp:  .fill 2");
    if (use_mul) line("__r:    .fill 2");
    if (use_mul || use_div || use_mod || use_shl || use_shr) line("__n:    .fill 1");
    if (use_div || use_mod) line("__dr:   .fill 2");
    return 0;
}

int emit_globals() {
    int i;
    int j;
    int e;
    i = 0;
    while (i < gcount) {
        emitstr("_g_"); emitstr(gpool + goff[i]);
        if (gcnt[i] > 0) {
            emitstr(":   .fill ");
            emitdec(gcnt[i] * type_size(gbase[i], gptr[i])); putchar(10);
        } else if (gbase[i] >= 2 && gptr[i] == 0) {   /* struct/union scalar */
            emitstr(":   .fill "); emitdec(type_size(gbase[i], 0)); putchar(10);
        } else if (ghas[i]) {
            emitstr(":   .word "); emitdec(gini[i] & 65535); putchar(10);
        } else {
            emitstr(":   .fill 2"); putchar(10);
        }
        i = i + 1;
    }
    i = 0;                                        /* string-literal pool */
    while (i < scount) {
        emitstr("__s"); emitdec(i); emitstr(":    .byte ");
        j = soff[i]; e = soff[i] + slen[i];
        while (j < e) { emitdec(spool[j] & 255); putchar(44); j = j + 1; }
        putchar(48); putchar(10);                 /* trailing NUL */
        i = i + 1;
    }
    return 0;
}

/* pre-scan the body (positioned at its '{') for the count of int/char locals,
   so the prologue can reserve the whole frame at once; then rewind. */
int count_locals() {                             /* total local bytes (arrays sized) */
    int save;
    int depth;
    int bytes;
    int base;
    int ptr;
    int n;
    save = spos;                                 /* spos is just past '{' */
    depth = 1;
    bytes = 0;
    while (depth > 0 && tok != T_EOF) {
        lex();
        if (is_punct("{")) depth = depth + 1;
        else if (is_punct("}")) depth = depth - 1;
        else if (tok == T_KW && (streq(tname, "int") || streq(tname, "char")
                                 || streq(tname, "struct") || streq(tname, "union"))) {
            if (streq(tname, "struct") || streq(tname, "union")) {
                lex(); base = 2 + find_struct(tname); lex();   /* 'struct' tag */
            } else {
                base = 0;
                if (streq(tname, "char")) base = 1;
                lex();
            }
            ptr = 0;
            while (is_punct("*")) { ptr = ptr + 1; lex(); }
            lex();                               /* name */
            if (is_punct("[")) {
                lex(); n = tval; lex();          /* '[' count -- ']' eaten by loop */
                bytes = bytes + n * type_size(base, ptr);
            } else {
                bytes = bytes + type_size(base, ptr);
            }
        }
    }
    spos = save;
    tok = T_PUNCT; tname[0] = 123; tname[1] = 0; /* restore current token '{' */
    return bytes;
}

int st_intern(char *s) {
    int o;
    o = stpooln;
    while (*s != 0) { stpool[stpooln] = *s; stpooln = stpooln + 1; s = s + 1; }
    stpool[stpooln] = 0; stpooln = stpooln + 1;
    return o;
}
int m_intern(char *s) {
    int o;
    o = mpooln;
    while (*s != 0) { mpool[mpooln] = *s; mpooln = mpooln + 1; s = s + 1; }
    mpool[mpooln] = 0; mpooln = mpooln + 1;
    return o;
}

/* register a `struct/union Tag { members };` definition (tok past the tag) */
int register_struct(int isunion, char *tag) {
    int off;
    int sz;
    int mbsz;
    int base;
    int cnt;
    stnoff[stcount] = st_intern(tag);
    stfirst[stcount] = mtotal;
    eat("{");
    off = 0; sz = 0;
    while (is_punct("}") == 0 && tok != T_EOF) {
        base = parse_type();                     /* member type; sets g_ptr */
        mnoff[mtotal] = m_intern(tname); lex();  /* member name */
        cnt = 0;
        if (is_punct("[")) { lex(); cnt = tval; lex(); eat("]"); }
        mbase[mtotal] = base; mptr[mtotal] = g_ptr; mcnt[mtotal] = cnt;
        if (cnt > 0) mbsz = cnt * type_size(base, g_ptr);
        else mbsz = type_size(base, g_ptr);
        if (isunion) { moff[mtotal] = 0; if (mbsz > sz) sz = mbsz; }
        else { moff[mtotal] = off; off = off + mbsz; }
        mtotal = mtotal + 1;
        eat(";");
    }
    eat("}"); eat(";");
    if (isunion) stsz[stcount] = sz;
    else stsz[stcount] = off;
    stnm[stcount] = mtotal - stfirst[stcount];
    stcount = stcount + 1;
    return 0;
}

/* ---- top-level declarations: functions (with params) and global vars ------ */
int toplevel() {
    char nm[64];
    char pn[64];
    int hasi;
    int v;
    int pcount;
    int i;
    int nl;
    int k;
    int rptr;
    int pbase;
    int gbas;
    if (tok == T_KW && (streq(tname, "struct") || streq(tname, "union"))) {
        char tag[64];
        int isunion;
        isunion = streq(tname, "union");
        lex();                                   /* 'struct' / 'union' */
        strcpy_(tag, tname); lex();              /* tag */
        if (is_punct("{")) { register_struct(isunion, tag); return 0; }
        gbas = 2 + find_struct(tag);             /* struct-typed declaration */
        g_ptr = 0;
        while (is_punct("*")) { g_ptr = g_ptr + 1; lex(); }
        rptr = g_ptr;
    } else {
        gbas = parse_type();                     /* return/var type; sets g_ptr */
        rptr = g_ptr;
    }
    strcpy_(nm, tname); lex();                   /* declared name */
    if (is_punct("(")) {                         /* function definition */
        lex();                                   /* '(' */
        vcount = 0; vpooln = 0; nlocoff = 0;     /* fresh scope */
        pcount = 0;
        if (is_punct(")") == 0) {
            pbase = parse_type();
            strcpy_(pn, tname); lex();
            addvar(pn, 0, pbase, g_ptr, 0);
            pcount = 1;
            while (is_punct(",")) {
                lex();
                pbase = parse_type();
                strcpy_(pn, tname); lex();
                addvar(pn, 0, pbase, g_ptr, 0);
                pcount = pcount + 1;
            }
        }
        eat(")");
        i = 0;                                    /* param i at __fp + 2*(pcount-i) */
        while (i < pcount) { vfoff[i] = 2 * (pcount - i); i = i + 1; }

        strcpy_(curfunc, nm);
        emitstr("_f_"); emitstr(nm); line(":");
        line("        JSR __enter"); use_enter = 1;
        nl = count_locals();                      /* total local bytes */
        if (nl > 0) {                             /* reserve locals: __csp -= nl */
            k = nlabel; nlabel = nlabel + 1;
            line("        LDA __csp");
            emitstr("        LDB #"); emitdec(nl); putchar(10);
            line("        SUB"); line("        STA __csp");
            emitjmp("JC", "Lfr", k);
            line("        LDA __csp+1"); line("        LDB #1"); line("        SUB");
            line("        STA __csp+1");
            emitlabel("Lfr", k);
        }
        block();
        emitstr("_ret_"); emitstr(nm); line(":");
        line("        JSR __leave"); use_leave = 1;
        line("        RTS");
        return 0;
    }
    hasi = 0; v = 0;                             /* global variable */
    pcount = 0;                                  /* reuse as array count */
    if (is_punct("[")) { lex(); pcount = tval; lex(); eat("]"); }
    if (pcount == 0 && is_punct("=")) {
        lex();
        if (is_punct("-")) { lex(); v = 0 - tval; }
        else v = tval;
        lex();
        hasi = 1;
    }
    eat(";");
    addglobal(nm, gbas, rptr, pcount, hasi, v);
    return 0;
}

/* ---- driver: compile one `int main() { ... }` to a runnable program -------- */
int main() {
    slurp();
    lex();                                       /* prime the first token */

    line("        .org $7A00");
    line("        LDA #0"); line("        STA __csp");      /* __csp = $F800 */
    line("        LDA #248"); line("        STA __csp+1");
    line("        JSR _f_main");
    line("        RTS");

    while (tok != T_EOF) toplevel();

    emit_runtime();
    emit_globals();
    return 0;
}
