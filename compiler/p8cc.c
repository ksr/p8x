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
 * locals and recursion; global int/char variables (optional constant
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
 * builtin, and struct/union types with . and -> member access.  This spans
 * the whole p8cc.py subset (it self-compiles); only larger inputs await
 * Milestone B (running on the P8X needs streaming, not more language).
 *
 * CODE GENERATION (rewritten 2026-09-12): emits the Tier A ISA exactly as
 * p8cc.py does -- frames on the hardware stack P3 (SUBP3/LDW/STW/LEAW (P3+d),
 * PHW argument pushes), ADDW/SUBW/ANDW/ORW/XORW on the __ax word, CMPW + one
 * branch for conditions, JMP.A for always-taken jumps, `.relax` for the rest.
 * See the CODE GENERATION section below for the two single-pass differences
 * (deferred leaf operands with a one-token peek; the LAST argument in __ax). */
#include <stdio.h>

/* ---- token kinds (globals w/ initializers, since the subset has no enum) -- */
int T_EOF = 0;
int T_NUM = 1;
int T_ID = 2;
int T_KW = 3;
int T_STR = 4;
int T_PUNCT = 5;

/* ---- scanner state -------------------------------------------------------- */
char src[131072];    /* whole source, NUL-terminated. Host-side buffer only —
                      * this compiler never runs on the P8X (Milestone B streams the
                      * source on-target), so the size costs the target nothing and
                      * there is no reason to keep it tight.
                      * History: 16 KB -> 32 KB when a clib-spliced command (~17 KB)
                      * overflowed it; 32 KB -> 64 KB (2026-07-16) when grep.c sat
                      * 205 bytes under the limit and adding one //#use pushed it
                      * over. Both times the overflow was SILENT (see slurp()).
                      * 64 KB -> 128 KB (2026-07-16) when p8cc.c itself grew past
                      * 64 KB and could no longer read itself — that one was NOT
                      * silent: slurp()'s guard named it in the output, which is the
                      * whole point of the toobig() mechanism. */
int srclen = 0;
int spos = 0;        /* scan cursor */
int tok = 0;         /* current token kind */
int tval = 0;        /* numeric value when tok == T_NUM */
char tname[128];      /* identifier / keyword / punctuation text */
char tstr[1024];      /* decoded bytes of the last T_STR token */
int tstrlen = 0;

/* ---- object-like //#define macros (name -> 16-bit value) ------------------ */
char mac_names[4096]; /* packed NUL-terminated macro names */
int  mac_vals[256];    /* parallel values (k-th name -> mac_vals[k]) */
int  mac_cnt = 0;
int  mac_end = 0;     /* next free offset in mac_names */
int  mac_hit = 0;     /* set by mac_lookup: 1 if the name is a macro */

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

int toobig(char *what);              /* defined with the other output helpers below */

/* ---- object-like //#define: parse one directive, and look a name up -------- */
/* mac_define: spos points just past "//#define"; read NAME then a dec/0xhex value. */
int mac_define() {
    int v;
    if (mac_cnt >= 256) { toobig("macros_256"); return 0; }   /* mac_vals[256] */
    while (src[spos] == 32 || src[spos] == 9) spos = spos + 1;
    while (is_alnum(src[spos])) {                 /* NAME -> packed pool */
        if (mac_end >= 4095) { toobig("mac_names_4096"); return 0; }
        mac_names[mac_end] = src[spos];
        mac_end = mac_end + 1;
        spos = spos + 1;
    }
    mac_names[mac_end] = 0;
    mac_end = mac_end + 1;
    while (src[spos] == 32 || src[spos] == 9) spos = spos + 1;
    v = 0;                                        /* value: 0x hex or decimal */
    if (src[spos] == 48 && (src[spos + 1] == 120 || src[spos + 1] == 88)) {
        spos = spos + 2;
        while (is_hex(src[spos])) { v = v * 16 + hexval(src[spos]); spos = spos + 1; }
    } else {
        while (is_digit(src[spos])) { v = v * 10 + (src[spos] - 48); spos = spos + 1; }
    }
    mac_vals[mac_cnt] = v;
    mac_cnt = mac_cnt + 1;
    return v;
}

/* mac_lookup: return the value of macro `name` (mac_hit=1), else 0 (mac_hit=0). */
int mac_lookup(char *name) {
    int p;
    int k;
    int j;
    int ok;
    p = 0;
    k = 0;
    mac_hit = 0;
    while (k < mac_cnt) {
        j = 0;
        ok = 1;
        while (mac_names[p + j] != 0 && ok) {
            if (mac_names[p + j] != name[j]) ok = 0;
            j = j + 1;
        }
        if (ok && name[j] == 0) {                 /* both terminated together */
            mac_hit = 1;
            return mac_vals[k];
        }
        while (mac_names[p] != 0) p = p + 1;       /* skip to next packed name */
        p = p + 1;
        k = k + 1;
    }
    return 0;
}

/* ---- read all of stdin into src[] ----------------------------------------- */
/* Bounded by sizeof(src)-1 so an oversized file truncates safely instead of
 * overflowing the buffer.  (src is a host-side 128 KB buffer; on-target — the
 * open Milestone B — this slurp would become a stream.) */
/* slurp: read the whole source into src[]. If it does not fit, say so LOUDLY.
 * This used to stop at the buffer end and carry on compiling the prefix — exit 0,
 * plausible-looking asm, half a program. It cost real debugging twice: grep.c
 * silently lost half its code and the only symptom was a missing match. Emitting
 * a bad directive makes the assembler reject the output with the reason attached,
 * which is the strongest failure this compiler can raise — it has no exit() and
 * no stderr, and stdout is the generated asm. */
int slurp() {
    int c;
    int n;
    n = 0;
    c = getchar();
    while (c != 0 && c != -1 && n < 131071) {   /* keep in step with src[131072] */
        src[n] = c;
        n = n + 1;
        c = getchar();
    }
    src[n] = 0;
    srclen = n;
    if (c != 0 && c != -1) {                 /* input remained -> src[] overflowed */
        puts("        .p8cc_source_too_large__raise_src_in_p8cc_c");
    }
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
            spos = spos + 2;
            if (src[spos] == 35 && src[spos + 1] == 100 && src[spos + 2] == 101
                && src[spos + 3] == 102 && src[spos + 4] == 105
                && src[spos + 5] == 110 && src[spos + 6] == 101) {  /* //#define */
                spos = spos + 7;
                mac_define();
            }
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
        } else if (c == 35) {                              /* # line: `#define NAME value`
                                                              is honoured like //#define;
                                                              any other directive is skipped */
            spos = spos + 1;
            if (src[spos] == 100 && src[spos + 1] == 101 && src[spos + 2] == 102
                && src[spos + 3] == 105 && src[spos + 4] == 110 && src[spos + 5] == 101
                && (src[spos + 6] == 32 || src[spos + 6] == 9)) {
                spos = spos + 6;
                mac_define();
            }
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
        /* Cap at 63, not tname's 127: every consumer copies tname into a char[64]
         * (factor's nm, decl's nm/pn/dn, struct's tag), so 64 is the real limit —
         * a longer name smashes a stack buffer before tname itself fills.
         * Keep consuming past the cap rather than returning early: spos must still
         * advance past the whole identifier or the parser re-lexes it forever. */
        while (is_alnum(src[spos])) {
            if (n < 63) { tname[n] = src[spos]; n = n + 1; }
            else if (n == 63) { toobig("identifier_longer_than_63_chars"); n = n + 1; }
            spos = spos + 1;
        }
        if (n > 63) n = 63;                                /* truncate; already reported */
        tname[n] = 0;
        if (is_keyword(tname)) { tok = T_KW; return tok; }
        tval = mac_lookup(tname);                          /* //#define macro -> NUMBER */
        if (mac_hit) { tok = T_NUM; return tok; }
        tok = T_ID;
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
        /* As with identifiers: past the cap keep scanning to the closing quote so
         * spos lands correctly, but stop storing. Report once, at the boundary. */
        while (src[spos] != 34 && src[spos] != 0) {
            if (n == 1023) { toobig("tstr_1024__string_literal_too_long"); n = n + 1; }
            if (src[spos] == 92) {                          /* backslash escape */
                spos = spos + 1;
                c = src[spos];
                if (n < 1023) {
                    if (c == 110) tstr[n] = 10;
                    else if (c == 116) tstr[n] = 9;
                    else if (c == 114) tstr[n] = 13;
                    else if (c == 48) tstr[n] = 0;
                    else tstr[n] = c;
                    n = n + 1;
                }
                spos = spos + 1;
            } else {
                if (n < 1023) { tstr[n] = src[spos]; n = n + 1; }
                spos = spos + 1;
            }
        }
        if (n > 1023) n = 1023;                             /* truncate; already reported */
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
int nlabel = 0;      /* unique-label counter */
int z16 = 0;         /* 1 right after an immediate word op (ADDW/ANDW/... __ax,#k): the
                        flags' Z is then the 16-bit zero test of __ax. Any other emitted
                        text clears it (see emitstr). */
int use_mul = 0;     /* runtime helpers actually referenced (emitted at the end) */
int use_div = 0;
int use_mod = 0;
int use_shl = 0;
int use_shr = 0;
int use_cmp16 = 0;

/* A type is (base, ptr) packed in one int: base in bit 0 (0=int, 1=char),
   pointer depth in bits 8+.  Expression functions also carry an lvalue flag in
   bit 1 (when set, __ax holds the object's ADDRESS, not its value). */
int g_ptr = 0;       /* pointer depth from the most recent parse_type() */

/* ---- global variable table (single-pass, declared before use) ------------- */
/* Fixed tables, NONE bounds-checked — overflow is SILENT and corrupts codegen
 * (the appenders below run off the end of one array into the next). They are sized
 * generously rather than guarded, because this compiler is HOST-ONLY: it never
 * runs on the P8X (apps/p8xcc.asm is the native one), so a big array costs the
 * target nothing. Sized 2026-07-16 from the largest real input, p8cc.c itself:
 * 168 globals, 781 string literals, 11,785 bytes of string text, 90 functions.
 * The headroom is 3x+ on every table.
 * Every one of them is GUARDED: on overflow the writer calls toobig() and returns
 * without storing, which emits an unparseable directive naming the table and makes
 * the assembler reject the build. That is the only failure this compiler can raise
 * — it has no error string, the subset has no exit(), and stdout IS the generated
 * asm. Silent truncation cost real debugging twice (src[] 16K->32K, then 32K->64K,
 * the second time losing half of grep with no symptom but a missing match), which
 * is why none of these fail quietly any more.
 * IF YOU RAISE A LIMIT HERE, raise the matching literal in the guard — the subset
 * has no #define (//#define is invisible to the host cc), so the bounds are spelled
 * out at both ends. The guard names in the poison text say which function to look
 * in. Identifiers are capped at 63 in lex(), not by tname[128]: consumers copy
 * tname into char[64] locals, so 64 is the real limit.
 * Do not shrink these to "save space" — there is no space to save on the host. */
char gpool[8192];    /* packed NUL-terminated names */
int gpooln = 0;
int goff[512];        /* name offset in gpool */
int gbase[512];       /* base type (0 int / 1 char) */
int gptr[512];        /* pointer depth */
int gcnt[512];        /* array element count (0 = scalar) */
int ghas[512];        /* has a constant initializer? */
int gini[512];        /* the initializer value */
int gcount = 0;

/* ---- string-literal pool (emitted as __sN: .byte ... at the end) ---------- */
char spool[32768];
int spooln = 0;
int soff[2048];        /* offset of string i in spool */
int slen[2048];        /* length of string i */
int scount = 0;

/* ---- per-function scope: params (frame offset +2,+4..) and locals (-2,-4..) */
char vpool[4096];     /* packed names of the current function's params+locals */
int vpooln = 0;
int vnoff[256];       /* name offset in vpool */
int vfoff[256];       /* frame offset relative to __fp */
int vbase[256];       /* base type */
int vptr[256];        /* pointer depth */
int vcnt[256];        /* array element count (0 = scalar) */
int vcount = 0;
int nlocoff = 0;     /* running frame offset for locals (grows negative) */
char curfunc[128];    /* name of the function being compiled (for _ret_) */

/* ---- variable lookup result ----------------------------------------------- */
int look_off = 0;        /* frame offset (locals/params) */
int look_base = 0;
int look_ptr = 0;
int look_cnt = 0;        /* array element count (0 = scalar) */
int look_isglobal = 0;

int emitstr(char *s) {
    z16 = 0;                         /* anything emitted invalidates the Z shortcut */
    while (*s != 0) { putchar(*s); s = s + 1; }
    return 0;
}

int line(char *s) { emitstr(s); putchar(10); return 0; }

/* toobig: a fixed table filled up. This is the ONLY way this compiler can report
 * a problem — it has no error string, the subset has no exit(), and stdout IS the
 * generated asm — so say it by emitting a directive the assembler cannot parse,
 * with the table's name in it. The build then stops on the real reason instead of
 * quietly producing a truncated program. Same trick as slurp(); see the note above
 * the table declarations.
 * Callers MUST return without writing after calling this — poisoning the output is
 * not enough on its own, since the out-of-bounds write is what corrupts the host. */
int toobig(char *what) {
    emitstr("        .p8cc_table_full__");
    emitstr(what);
    emitstr("__raise_it_in_p8cc_c");
    putchar(10);
    return 0;
}

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
    while (*s != 0) {
        if (gpooln >= 8191) { toobig("gpool_8192"); return off; }
        gpool[gpooln] = *s; gpooln = gpooln + 1; s = s + 1;
    }
    gpool[gpooln] = 0; gpooln = gpooln + 1;
    return off;
}

int addglobal(char *nm, int base, int ptr, int cnt, int hasi, int v) {
    if (gcount >= 512) { toobig("globals_512"); return 0; }   /* goff/gbase/... [512] */
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
    while (*s != 0) {
        if (vpooln >= 4095) { toobig("vpool_4096"); return off; }
        vpool[vpooln] = *s; vpooln = vpooln + 1; s = s + 1;
    }
    vpool[vpooln] = 0; vpooln = vpooln + 1;
    return off;
}

int addvar(char *nm, int foff, int base, int ptr, int cnt) {
    if (vcount >= 256) { toobig("locals_256__params_plus_locals_in_one_fn"); return 0; }
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
char stpool[2048];    /* tag names */
int stpooln = 0;
int stnoff[128];      /* tag name offset */
int stsz[128];        /* total size in bytes */
int stfirst[128];     /* index of first member in the flat member arrays */
int stnm[128];        /* number of members */
int stcount = 0;
char mpool[8192];    /* member names (flat across all structs) */
int mpooln = 0;
int mnoff[1024];      /* member name offset */
int moff[1024];       /* member offset within its struct */
int mbase[1024];      /* member base type */
int mptr[1024];       /* member pointer depth */
int mcnt[1024];       /* member array count (0 = scalar) */
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


/* ==== CODE GENERATION (rewritten 2026-09-12 for the Tier A ISA) ==============
 * Model (matches p8cc.py): the 16-bit pseudo-accumulator __ax holds expression
 * results; call frames live on the hardware stack P3 (SUBP3 #L reserves the
 * locals, every local is LDW/STW/LEAW (P3+d)); + - & | ^ are ADDW/SUBW/ANDW/
 * ORW/XORW on __ax; comparisons are one CMPW and one branch; multiply, divide
 * and the shifts call small runtime helpers.
 *
 * Because this compiler is SINGLE-PASS (it emits while it parses) two things
 * differ from the two-pass Python compiler:
 *   * a LEAF operand (constant, scalar variable, string, array address) is not
 *     emitted when parsed but recorded as PENDING (pk/pval/...) and emitted
 *     only when its use is known -- as an immediate (`ADDW __ax,#3`), a `__t`
 *     load, a byte into A, or a full __ax load. A one-token peek decides whether
 *     the RIGHT operand of a binary op is a leaf, so the left value is only
 *     spilled to the stack when the right side really needs code;
 *   * arguments are parsed left to right, so the LAST argument travels in __ax
 *     (p8cc.py passes the first) and the others are pushed left to right:
 *     param i (of n, i < n-1) sits at P3+L+3+2*(n-2-i); the last one gets the
 *     first local slot (P3+1) when the body names it. Each compiler's callees
 *     match its own callers, so programs are self-consistent.
 * Conditions (if/while/for/&&) are parsed in a JUMP-IF-FALSE mode: a relational
 * or equality at the top of the condition emits `CMPW ; Jcc else` directly
 * (cdone=1) instead of a 0/1 value; a `||` at the top level of a condition
 * (pre-scanned) falls back to a value test. Not ported from p8cc.py: the narrow
 * 8-bit paths beyond putchar/bios/byte stores, and dead-function elimination.
 * Taken relaxed branches clobber A and the flags (2026-09-12), so nothing here
 * reads A or the flags after a taken branch; unconditional jumps are JMP.A.
 */
int cursp = 0;        /* bytes the compiler has pushed on P3 in the current expression */
int framel = 0;       /* L: bytes of locals reserved by SUBP3 in the current function */
int cmode = 0;        /* 1: parsing a condition -- relops may branch instead of valuing */
int clabel = 0;       /* ... the label to jump to when the condition is FALSE */
int cdone = 0;        /* ... set when a branch was emitted (no value left in __ax) */
int stmt_expr = 0;    /* 1 while parsing an expression STATEMENT (value unused) */

/* pending operand (see the header) */
int pk = 0;           /* 0 none (value/address in __ax), 1 constant, 2 scalar variable,
                         3 string literal, 4 array address (global or local) */
int pval = 0;         /* constant value / string index */
int pglob = 0;        /* variable/array: 1 global, 0 local */
int poff = 0;         /* local: frame offset (from P3+0, before cursp) */
int pbase = 0;        /* variable type */
int pptr = 0;
char pname[64];       /* global name */

int emitd(int v) { emitdec(v & 65535); return 0; }
int dsp(int off) { return off + cursp; }   /* displacement of a frame slot RIGHT NOW */
int emit_p3(int d) { emitstr("(P3+"); emitdec(d); putchar(41); return 0; }   /* ')' */

/* Frame slots beyond a 255-byte displacement (big local arrays) take the FAR
   path: __la = P3 + d, then P1 = __la and (P1) accesses. Same as p8cc.py. */
int use_la = 0;
int far_la(int d) {                   /* __la = P3 + d */
    use_la = 1;
    line("        TPA3L"); line("        STA __la"); line("        TPA3H"); line("        STA __la+1");
    emitstr("        ADDW __la,#"); emitdec(d); putchar(10);
    return 0;
}
int far_p1(int d) { far_la(d); line("        LPW1 __la"); return 0; }   /* P1 = P3 + d */
int ld_local(char *dst, int d) {      /* word dst := frame slot at d */
    if (d <= 255) { emitstr("        LDW "); emitstr(dst); putchar(44); emit_p3(d); putchar(10); return 0; }
    far_p1(d);
    line("        LDA (P1)+"); emitstr("        STA "); line(dst);
    line("        LDA (P1)"); emitstr("        STA "); emitstr(dst); line("+1");
    return 0;
}
int lea_local(char *dst, int d) {     /* word dst := address of the frame slot */
    if (d <= 255) { emitstr("        LEAW "); emitstr(dst); putchar(44); emit_p3(d); putchar(10); return 0; }
    far_la(d); emitstr("        MOVW "); emitstr(dst); line(",__la");
    return 0;
}
int st_local_word(int d) {            /* frame slot at d := __ax */
    if (d <= 255) { emitstr("        STW "); emit_p3(d); line(",__ax"); return 0; }
    far_p1(d);
    line("        LDA __ax"); line("        STA (P1)+"); line("        LDA __ax+1"); line("        STA (P1)");
    return 0;
}
int st_local_byte(int d) {            /* char slot at d := A, high byte := 0 */
    if (d <= 254) {
        emitstr("        STA "); emit_p3(d); putchar(10);
        line("        LDA #0"); emitstr("        STA "); emit_p3(d + 1); putchar(10);
        return 0;
    }
    line("        STA __c"); far_p1(d);
    line("        LDA __c"); line("        STA (P1)+"); line("        LDA #0"); line("        STA (P1)");
    return 0;
}
int ld_local_a(int d) {               /* A := low byte of the slot */
    if (d <= 255) { emitstr("        LDA "); emit_p3(d); putchar(10); return 0; }
    far_p1(d); line("        LDA (P1)");
    return 0;
}

/* --- moving a pending operand where it is needed ----------------------------- */
int psize() { return type_size(pbase, pptr); }        /* size of the pending variable */

int flush_val() {                     /* __ax = the pending VALUE; pk = 0 */
    if (pk == 1) { emitstr("        LDW __ax,#"); emitd(pval); putchar(10); }
    else if (pk == 3) { emitstr("        LDW __ax,#__s"); emitdec(pval); putchar(10); }
    else if (pk == 4) {
        if (pglob) { emitstr("        LDW __ax,#_g_"); emitstr(pname); putchar(10); }
        else lea_local("__ax", dsp(poff));
    } else if (pk == 2) {
        if (pglob == 0) ld_local("__ax", dsp(poff));
        else if (psize() == 2) { emitstr("        MOVW __ax,_g_"); emitstr(pname); putchar(10); }
        else {
            emitstr("        LDA _g_"); emitstr(pname); putchar(10);
            line("        STA __ax"); line("        LDA #0"); line("        STA __ax+1");
        }
    }
    pk = 0;
    return 0;
}
int flush_addr() {                    /* __ax = the ADDRESS of the pending variable */
    if (pk == 2 || pk == 4) {
        if (pglob) { emitstr("        LDW __ax,#_g_"); emitstr(pname); putchar(10); }
        else lea_local("__ax", dsp(poff));
    } else if (pk != 0) {
        flush_val();                  /* (a constant/string has no address: value) */
    }
    pk = 0;
    return 0;
}
int leaf_t() {                        /* __t = the pending value (pk must be != 0) */
    if (pk == 1) { emitstr("        LDW __t,#"); emitd(pval); putchar(10); }
    else if (pk == 3) { emitstr("        LDW __t,#__s"); emitdec(pval); putchar(10); }
    else if (pk == 4) {
        if (pglob) { emitstr("        LDW __t,#_g_"); emitstr(pname); putchar(10); }
        else lea_local("__t", dsp(poff));
    } else if (pk == 2) {
        if (pglob == 0) ld_local("__t", dsp(poff));
        else if (psize() == 2) { emitstr("        MOVW __t,_g_"); emitstr(pname); putchar(10); }
        else {
            emitstr("        LDA _g_"); emitstr(pname); putchar(10);
            line("        STA __t"); line("        LDA #0"); line("        STA __t+1");
        }
    }
    pk = 0;
    return 0;
}
int byte_a() {                        /* A = low byte of the value (pending or __ax) */
    if (pk == 1) { emitstr("        LDA #"); emitdec(pval & 255); putchar(10); pk = 0; return 0; }
    if (pk == 2) {
        if (pglob) { emitstr("        LDA _g_"); emitstr(pname); putchar(10); }
        else ld_local_a(dsp(poff));
        pk = 0; return 0;
    }
    flush_val();
    line("        LDA __ax");
    return 0;
}

int pend_set(int k, int v, int g, int o, int b, int p, char *nm) {   /* restore a saved pending */
    pk = k; pval = v; pglob = g; poff = o; pbase = b; pptr = p; strcpy_(pname, nm);
    return 0;
}

int push_val() {                      /* push the value (pending or __ax) on P3 */
    if (pk == 2 && pglob == 0 && dsp(poff) <= 255) { emitstr("        PHW "); emit_p3(dsp(poff)); putchar(10); pk = 0; }
    else if (pk == 2 && psize() == 2) { emitstr("        PHW _g_"); emitstr(pname); putchar(10); pk = 0; }
    else { flush_val(); line("        PHW __ax"); }
    cursp = cursp + 2;
    return 0;
}
int pop_t() { line("        PLW __t"); cursp = cursp - 2; return 0; }

int emitlabel(char *base, int n) {
    emitstr(base); emitdec(n); putchar(58); putchar(10);   /* ':' = 58 */
    return 0;
}
int emitjmp(char *op, char *base, int n) {                 /* op base<n> */
    emitstr("        "); emitstr(op); putchar(32);
    emitstr(base); emitdec(n); putchar(10);
    return 0;
}
int newlabel() { int k; k = nlabel; nlabel = nlabel + 1; return k; }

int test_ax_z() {                     /* flags Z := (__ax == 0), unless already so */
    flush_val();
    if (z16 == 0) line("        CMPW __ax,#0");
    return 0;
}

int addconst_ax(int k) {              /* __ax += k (16-bit constant) */
    k = k & 65535;
    if (k == 0) return 0;
    if (k == 1) { line("        INCW __ax"); return 0; }
    emitstr("        ADDW __ax,#"); emitd(k); putchar(10);
    return 0;
}

/* --- runtime helpers (emitted only if used) ---------------------------------- */
int emit_mul() {
    line("__mul:  LDA #0");     line("        STA __r");   line("        STA __r+1");
    line("        LDA #16");    line("        STA __n");
    line("__mul_l: LDA __ax");  line("        LDB #1");    line("        AND");
    line("        JZ __mul_s");
    line("        LDA __r");    line("        LDB __t");   line("        ADD");
    line("        STA __r");    line("        LDA #0");    line("        ROL");
    line("        STA __c");    line("        LDA __r+1");
    line("        LDB __t+1");  line("        ADD");       line("        LDB __c");
    line("        ADD");        line("        STA __r+1");
    line("__mul_s: LDA __t");   line("        SHL");       line("        STA __t");
    line("        LDA __t+1");  line("        ROL");       line("        STA __t+1");
    line("        LDA __ax+1"); line("        SHR");       line("        STA __ax+1");
    line("        LDA __ax");   line("        ROR");       line("        STA __ax");
    line("        LDA __n");    line("        DEC");       line("        STA __n");
    line("        JNZ __mul_l");
    line("        MOVW __ax,__r"); line("        RTS");
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
    line("        JZ __dm_lo"); line("        JC __dm_ge");line("        JMP.A __dm_no");
    line("__dm_lo: LDA __dr");  line("        LDB __ax");  line("        CMP");
    line("        JNC __dm_no");
    line("__dm_ge: LDA __dr");  line("        LDB __ax");  line("        SUB");
    line("        STA __dr");   line("        LDA #0");    line("        ROL");
    line("        LDB #1");     line("        XOR");       line("        STA __c");
    line("        LDA __dr+1"); line("        LDB __ax+1");line("        SUB");
    line("        LDB __c");    line("        SUB");       line("        STA __dr+1");
    line("        LDA __t");    line("        LDB #1");    line("        OR");
    line("        STA __t");
    line("__dm_no: LDA __n");   line("        DEC");       line("        STA __n");
    line("        JNZ __dm_l"); line("        RTS");
    return 0;
}
int emit_div() { line("__div:  JSR __divmod"); line("        MOVW __ax,__t");  line("        RTS"); return 0; }
int emit_mod() { line("__mod:  JSR __divmod"); line("        MOVW __ax,__dr"); line("        RTS"); return 0; }
int emit_shl() {
    line("__shl:  LDA __ax");   line("        STA __n");   line("        MOVW __ax,__t");
    line("__shl_l: LDA __n");   line("        JZ __shl_e");
    line("        LDA __ax");   line("        SHL");       line("        STA __ax");
    line("        LDA __ax+1"); line("        ROL");       line("        STA __ax+1");
    line("        LDA __n");    line("        DEC");       line("        STA __n");
    line("        JMP.A __shl_l"); line("__shl_e: RTS");
    return 0;
}
int emit_shr() {
    line("__shr:  LDA __ax");   line("        STA __n");   line("        MOVW __ax,__t");
    line("__shr_l: LDA __n");   line("        JZ __shr_e");
    line("        LDA __ax+1"); line("        SHR");       line("        STA __ax+1");
    line("        LDA __ax");   line("        ROR");       line("        STA __ax");
    line("        LDA __n");    line("        DEC");       line("        STA __n");
    line("        JMP.A __shr_l"); line("__shr_e: RTS");
    return 0;
}
int emit_cmp16() {                    /* Z := (__t == __ax), 16-bit, branch-free */
    line("__cmp16: LDA __t");   line("        LDB __ax");  line("        SUB");
    line("        STA __c");    line("        LDA __t+1"); line("        LDB __ax+1");
    line("        SUB");        line("        LDB __c");   line("        OR");
    line("        RTS");
    return 0;
}

/* --- lvalue / type-aware primitives ------------------------------------------ */
int deref_load(int sz) {              /* __ax holds an address -> load the value */
    line("        LPW1 __ax");
    if (sz == 2) {
        line("        LDA (P1)+"); line("        STA __ax");
        line("        LDA (P1)"); line("        STA __ax+1");
    } else {
        line("        LDA (P1)"); line("        STA __ax");
        line("        LDA #0"); line("        STA __ax+1");
    }
    return 0;
}

int rvalue(int ty) {                  /* an lvalue -> its value (pending stays pending) */
    if (ty_lval(ty)) {
        if (pk == 2) return mkty(ty_base(ty), ty_ptr(ty), 0);
        if (pk != 0) flush_val();     /* (should not happen: only variables are lvalues) */
        deref_load(ty_size(ty));
        return mkty(ty_base(ty), ty_ptr(ty), 0);
    }
    return ty;
}

int scale2_ax() {                     /* __ax <<= 1 (int-pointer element size) */
    line("        LDA __ax"); line("        SHL"); line("        STA __ax");
    line("        LDA __ax+1"); line("        ROL"); line("        STA __ax+1");
    return 0;
}
int scale2_t() {                      /* __t <<= 1 */
    line("        LDA __t"); line("        SHL"); line("        STA __t");
    line("        LDA __t+1"); line("        ROL"); line("        STA __t+1");
    return 0;
}

int parse_type() {                    /* tok at a type kw -> base; sets g_ptr */
    int base;
    if (streq(tname, "struct") || streq(tname, "union")) {
        lex();                        /* 'struct' / 'union' */
        base = 2 + find_struct(tname);
        lex();                        /* tag */
    } else {
        base = 0;
        if (streq(tname, "char")) base = 1;
        lex();
    }
    g_ptr = 0;
    while (is_punct("*")) { g_ptr = g_ptr + 1; lex(); }
    return base;
}

/* --- function return types (declared before use: prototypes or definitions) --- */
char fpool[4096];
int fpooln = 0;
int fnoff[256];
int fbase[256];
int fptr[256];
int fcount = 0;
int addfunc(char *nm, int base, int ptr) {
    int i;
    i = 0;
    while (i < fcount) { if (streq(fpool + fnoff[i], nm)) return 0; i = i + 1; }   /* known */
    if (fcount >= 256 || fpooln + 64 >= 4096) { toobig("functions_256"); return 0; }
    fnoff[fcount] = fpooln;
    while (*nm != 0) { fpool[fpooln] = *nm; fpooln = fpooln + 1; nm = nm + 1; }
    fpool[fpooln] = 0; fpooln = fpooln + 1;
    fbase[fcount] = base; fptr[fcount] = ptr;
    fcount = fcount + 1;
    return 0;
}
int functype(char *nm) {              /* -> the call's result type (int if unknown) */
    int i;
    i = 0;
    while (i < fcount) { if (streq(fpool + fnoff[i], nm)) return mkty(fbase[i], fptr[i], 0); i = i + 1; }
    return mkty(0, 0, 0);
}

/* --- lexer save/restore, for the peeks --------------------------------------- */
int sv_spos = 0;
int sv_tok = 0;
int sv_tval = 0;
char sv_name[128];
int lex_save() { sv_spos = spos; sv_tok = tok; sv_tval = tval; strcpy_(sv_name, tname); return 0; }
int lex_restore() { spos = sv_spos; tok = sv_tok; tval = sv_tval; strcpy_(tname, sv_name); return 0; }

int oplevel(char *p) {                /* binary-operator precedence level 1..8, 0 if none */
    if (streq(p, "|")) return 1;
    if (streq(p, "^")) return 2;
    if (streq(p, "&")) return 3;
    if (streq(p, "==") || streq(p, "!=")) return 4;
    if (streq(p, "<") || streq(p, ">") || streq(p, "<=") || streq(p, ">=")) return 5;
    if (streq(p, "<<") || streq(p, ">>")) return 6;
    if (streq(p, "+") || streq(p, "-")) return 7;
    if (streq(p, "*") || streq(p, "/") || streq(p, "%")) return 8;
    return 0;
}

/* peek_leaf: is the operand that starts at the current token a LEAF for a
 * binary operator of `level` -- a constant, string, scalar variable or array
 * name followed by nothing that binds tighter (no postfix, no higher-level
 * operator)? Restores the lexer. The one lookahead this compiler does. */
int peek_leaf(int level) {
    int ok;
    int lv;
    ok = 0;
    lex_save();
    if (tok == T_NUM || tok == T_STR) ok = 1;
    else if (tok == T_ID) {
        if (lookup(tname)) {
            ok = 1;
            if (look_cnt == 0 && look_base >= 2 && look_ptr == 0) ok = 0;   /* a struct value */
        }
    }
    if (ok) {
        lex();                        /* the token after the operand */
        if (tok == T_PUNCT) {
            if (is_punct("(") || is_punct("[") || is_punct(".") || is_punct("->")) ok = 0;
            else {
                lv = oplevel(tname);
                if (lv > level) ok = 0;   /* binds tighter: not a leaf for us */
            }
        }
    }
    lex_restore();
    return ok;
}

/* cond_has_or: from the current token, does the parenthesised condition contain
 * a `||` at its top level before the closing `)` / `;`?  Restores the lexer. */
int cond_has_or(int untilsemi) {
    int depth;
    int found;
    depth = 0; found = 0;
    lex_save();
    while (tok != T_EOF) {
        if (is_punct("(") || is_punct("[")) depth = depth + 1;
        else if (is_punct(")") || is_punct("]")) {
            if (depth == 0) { lex_restore(); return found; }
            depth = depth - 1;
        } else if (untilsemi && depth == 0 && is_punct(";")) { lex_restore(); return found; }
        else if (depth == 0 && is_punct("||")) found = 1;
        lex();
    }
    lex_restore();
    return found;
}

/* pre-scan the body (positioned at its '{') for its local declarations, so
   the prologue can reserve the whole frame at once and every local gets a
   slot BEFORE any statement is compiled: SCALARS FIRST (they stay inside the
   255-byte displacement window), arrays and structs above them -- the same
   layout as p8cc.py. A char scalar owns a 2-byte slot (zero high byte). The
   first declaration of a name wins (nested blocks reuse it). Rewinds. */
char pre_pool[4096];  /* names of the current function's locals */
int pre_pooln = 0;
int pre_noff[256];
int pre_sz[256];
int pre_aggr[256];    /* 1: array / struct (allocated above the scalars) */
int pre_foff[256];    /* the assigned frame offset */
int pre_cnt = 0;
int pre_lookup(char *nm) {           /* -> index, or -1 */
    int i;
    i = 0;
    while (i < pre_cnt) { if (streq(pre_pool + pre_noff[i], nm)) return i; i = i + 1; }
    return 0 - 1;
}
int count_locals(int start) {        /* -> total local bytes; slots from `start` */
    int save;
    int depth;
    int bytes;
    int base;
    int ptr;
    int n;
    int i;
    int off;
    save = spos;                                 /* spos is just past '{' */
    depth = 1;
    pre_cnt = 0; pre_pooln = 0;
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
            if (pre_lookup(tname) < 0 && pre_cnt < 256 && pre_pooln + 64 < 4096) {
                pre_noff[pre_cnt] = pre_pooln;
                i = 0;
                while (tname[i] != 0) { pre_pool[pre_pooln] = tname[i]; pre_pooln = pre_pooln + 1; i = i + 1; }
                pre_pool[pre_pooln] = 0; pre_pooln = pre_pooln + 1;
                lex();                           /* name */
                if (is_punct("[")) {
                    lex(); n = tval; lex();      /* '[' count -- ']' eaten by loop */
                    pre_sz[pre_cnt] = n * type_size(base, ptr); pre_aggr[pre_cnt] = 1;
                } else {
                    n = type_size(base, ptr);
                    if (n == 1) n = 2;
                    pre_sz[pre_cnt] = n;
                    pre_aggr[pre_cnt] = 0;
                    if (ptr == 0 && base >= 2) pre_aggr[pre_cnt] = 1;   /* a struct value */
                }
                pre_cnt = pre_cnt + 1;
            } else {
                lex();                           /* a redeclared name: same slot */
                if (is_punct("[")) { lex(); lex(); }
            }
        }
    }
    if (pre_cnt >= 256) toobig("locals_256__declarations_in_one_fn");
    off = start; bytes = 0;                      /* assign: scalars first, then aggregates */
    i = 0;
    while (i < pre_cnt) {
        if (pre_aggr[i] == 0) { pre_foff[i] = off; off = off + pre_sz[i]; bytes = bytes + pre_sz[i]; }
        i = i + 1;
    }
    i = 0;
    while (i < pre_cnt) {
        if (pre_aggr[i]) { pre_foff[i] = off; off = off + pre_sz[i]; bytes = bytes + pre_sz[i]; }
        i = i + 1;
    }
    spos = save;
    tok = T_PUNCT; tname[0] = 123; tname[1] = 0; /* restore current token '{' */
    return bytes;
}


/* --- the expression grammar ---------------------------------------------------
   Each function returns the TYPE of what it produced. The value is in __ax or
   PENDING (pk != 0); a bare lvalue variable is pending with the lval bit set,
   a computed lvalue (*p, a[i], x.m) is its ADDRESS in __ax with the lval bit. */
int expr();
int stmt();
int binexpr(int level);

int materialize_c(int want_c) {       /* __ax = 0/1 from C == want_c */
    int lt;
    int le;
    lt = newlabel(); le = newlabel();
    if (want_c) emitjmp("JC", "Lt", lt); else emitjmp("JNC", "Lt", lt);
    line("        LDW __ax,#0"); emitjmp("JMP.A", "Le", le);
    emitlabel("Lt", lt); line("        LDW __ax,#1"); emitlabel("Le", le);
    return 0;
}
int materialize_z(int want_z) {       /* __ax = 0/1 from Z == want_z */
    int lt;
    int le;
    lt = newlabel(); le = newlabel();
    if (want_z) emitjmp("JZ", "Lt", lt); else emitjmp("JNZ", "Lt", lt);
    line("        LDW __ax,#0"); emitjmp("JMP.A", "Le", le);
    emitlabel("Lt", lt); line("        LDW __ax,#1"); emitlabel("Le", le);
    return 0;
}
int cond_tail() {                     /* in cond mode: may the relop branch here? */
    if (cmode == 0) return 0;
    if (is_punct(")") || is_punct(";") || is_punct("&&")) return 1;
    return 0;
}

int call_args(char *nm) {             /* user call: args left to right, LAST in __ax */
    int nargs;
    nargs = 0;
    if (is_punct(")") == 0) {
        rvalue(expr());
        nargs = 1;
        while (is_punct(",")) {
            push_val();               /* not the last: onto the stack */
            lex(); rvalue(expr());
            nargs = nargs + 1;
        }
        flush_val();                  /* the last argument: in __ax */
    }
    eat(")");
    emitstr("        JSR _f_"); emitstr(nm); putchar(10);
    if (nargs > 1) {
        emitstr("        ADDP3 #"); emitdec(2 * (nargs - 1)); putchar(10);
        cursp = cursp - 2 * (nargs - 1);
    }
    return 0;
}

int factor() {
    char nm[64];
    int k;
    int ty;
    int j;
    int esz;
    int addr;
    int lk; int lv; int lg; int lo; int lb; int lp; char lname[64];
    int pushed;
    int save_cmode;
    ty = mkty(0, 0, 0);
    pk = 0;
    if (tok == T_NUM) { pk = 1; pval = tval; lex(); ty = mkty(0, 0, 0); }
    else if (tok == T_STR) {                      /* string literal -> char* (pending) */
        if (scount >= 2048 || spooln + tstrlen >= 32768) {
            if (scount >= 2048) toobig("strings_2048");
            else toobig("spool_32768");
            lex();
            return mkty(1, 1, 0);
        }
        k = scount; scount = scount + 1;
        soff[k] = spooln; slen[k] = tstrlen;
        j = 0;
        while (j < tstrlen) { spool[spooln] = tstr[j]; spooln = spooln + 1; j = j + 1; }
        pk = 3; pval = k;
        lex();
        ty = mkty(1, 1, 0);
    }
    else if (is_punct("(")) {                     /* a parenthesised VALUE (never a condition) */
        save_cmode = cmode; cmode = 0;
        lex(); ty = expr(); eat(")");
        cmode = save_cmode;
    }
    else if (tok == T_ID) {
        strcpy_(nm, tname); lex();
        if (is_punct("(")) {                      /* call / builtin -> int rvalue */
            lex();                                /* '(' */
            save_cmode = cmode; cmode = 0;        /* arguments are VALUES */
            if (streq(nm, "getchar")) {           /* OS SYS_GETC -> char, -1 at EOF */
                eat(")");
                line("        JSR $200C"); line("        STA __ax");
                line("        LDA #0"); line("        STA __ax+1");
                k = newlabel();
                emitjmp("JNC", "Lge", k);         /* carry = end of (file) input */
                line("        LDW __ax,#65535");
                emitlabel("Lge", k);
            } else if (streq(nm, "putchar")) {    /* OS SYS_PUTC (redirectable) */
                rvalue(expr()); eat(")");
                byte_a(); line("        JSR $2009");
            } else if (streq(nm, "puts")) {       /* OS SYS_PUTS + newline */
                rvalue(expr()); eat(")"); flush_val();
                line("        LPW1 __ax");
                line("        JSR $200F"); line("        LDA #10"); line("        JSR $2009");
            } else if (streq(nm, "peek")) {       /* peek(addr) -> byte */
                rvalue(expr()); eat(")"); flush_val();
                line("        LPW1 __ax");
                line("        LDA (P1)"); line("        STA __ax");
                line("        LDA #0"); line("        STA __ax+1");
            } else if (streq(nm, "poke")) {       /* poke(addr, val) */
                rvalue(expr()); push_val();
                eat(","); rvalue(expr()); eat(")");
                pop_t();                          /* __t = addr */
                line("        LPW1 __t");
                byte_a(); line("        STA (P1)");
            } else if (streq(nm, "argstr")) {     /* P2 (program arg tail) -> char* */
                eat(")");
                line("        TPA2L"); line("        STA __ax");
                line("        TPA2H"); line("        STA __ax+1");
            } else if (streq(nm, "bios")) {       /* bios(constaddr, p1, a) -> A|carry<<8 */
                if (tok != T_NUM) line("; ERROR: bios addr not constant");
                addr = tval; lex();
                eat(","); rvalue(expr()); push_val();  /* P1 operand */
                eat(","); rvalue(expr()); eat(")");    /* A operand */
                pop_t();                               /* __t = P1 operand */
                line("        LPW1 __t");
                byte_a();
                emitstr("        JSR "); emitdec(addr); putchar(10);
                line("        STA __ax"); line("        LDA #0"); line("        ROL");
                line("        STA __ax+1");            /* carry -> bit 8, no branch */
            } else {                              /* user function */
                call_args(nm);
            }
            cmode = save_cmode;
            ty = mkty(0, 0, 0);
            if (streq(nm, "argstr")) ty = mkty(1, 1, 0);          /* char* */
            else if (streq(nm, "getchar") || streq(nm, "putchar") || streq(nm, "puts")
                     || streq(nm, "peek") || streq(nm, "poke") || streq(nm, "bios")) ty = mkty(0, 0, 0);
            else ty = functype(nm);               /* the declared return type (int* scales) */
        } else if (lookup(nm) == 0) {
            line("; ERROR: undeclared id"); ty = mkty(0, 0, 0);
        } else {                                  /* a variable: PENDING */
            pglob = look_isglobal; poff = look_off; pbase = look_base; pptr = look_ptr;
            strcpy_(pname, nm);
            if (look_cnt > 0) { pk = 4; ty = mkty(look_base, look_ptr + 1, 0); }  /* array decays */
            else { pk = 2; ty = mkty(look_base, look_ptr, 1); }                  /* scalar lvalue */
        }
    } else {
        line("; ERROR: bad factor");
    }

    while (is_punct("[") || is_punct(".") || is_punct("->")) {
        if (is_punct("[")) {                      /* e[i] -> address e + i*esz, lvalue */
            lex();
            ty = rvalue(ty);                      /* the pointer: pending or in __ax */
            esz = elem_size(ty);
            pushed = 0; lk = pk;
            if (pk == 0) { if (peek_leaf(0) == 0) { push_val(); pushed = 1; } }
            else { lv = pval; lg = pglob; lo = poff; lb = pbase; lp = pptr; strcpy_(lname, pname); pk = 0; }
            save_cmode = cmode; cmode = 0;        /* the index is a VALUE */
            rvalue(expr());                       /* the index */
            cmode = save_cmode;
            eat("]");
            if (pushed) {                         /* __ax = index, stack = pointer */
                flush_val();
                if (esz == 2) scale2_ax();
                pop_t(); line("        ADDW __ax,__t");
            } else if (lk != 0 && pk == 1) {      /* pointer leaf + constant index */
                k = pval * esz;
                pend_set(lk, lv, lg, lo, lb, lp, lname);
                flush_val(); addconst_ax(k);
            } else if (lk != 0) {                 /* pointer leaf + index (leaf or in __ax) */
                flush_val();                      /* __ax = index */
                if (esz == 2) scale2_ax();
                pend_set(lk, lv, lg, lo, lb, lp, lname);
                leaf_t(); line("        ADDW __ax,__t");
            } else if (pk == 1) {                 /* pointer in __ax, constant index */
                k = pval * esz; pk = 0; addconst_ax(k);
            } else {                              /* pointer in __ax, index leaf */
                leaf_t();
                if (esz == 2) scale2_t();
                line("        ADDW __ax,__t");
            }
            ty = mkty(ty_base(ty), ty_ptr(ty) - 1, 1);
        } else if (is_punct(".")) {               /* x.m : address of x + offset */
            lex();
            flush_addr();                         /* the struct's address into __ax */
            find_member(ty_base(ty) - 2, tname); lex();
            addconst_ax(mm_off);
            if (mm_cnt > 0) ty = mkty(mm_base, mm_ptr + 1, 0);
            else ty = mkty(mm_base, mm_ptr, 1);
        } else {                                  /* p->m : *p + offset */
            lex();
            ty = rvalue(ty); flush_val();         /* the pointer value into __ax */
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
    int save_cmode;
    if (is_punct("&")) {                          /* &lvalue -> its address */
        lex(); ty = unary();
        if (pk != 0) flush_addr();                /* a variable: LEAW / LDW #label */
        return mkty(ty_base(ty), ty_ptr(ty) + 1, 0);
    }
    if (is_punct("*")) {                          /* *ptr: lvalue at the pointer value */
        lex(); ty = rvalue(unary()); flush_val();
        return mkty(ty_base(ty), ty_ptr(ty) - 1, 1);
    }
    if (is_punct("-")) {
        lex(); rvalue(unary());
        if (pk == 1) { pval = (0 - pval) & 65535; return mkty(0, 0, 0); }   /* fold */
        flush_val(); line("        XORW __ax,#65535"); line("        INCW __ax");
        return mkty(0, 0, 0);
    }
    if (is_punct("~")) {
        lex(); rvalue(unary());
        if (pk == 1) { pval = (65535 - pval) & 65535; return mkty(0, 0, 0); }
        flush_val(); line("        XORW __ax,#65535");
        return mkty(0, 0, 0);
    }
    if (is_punct("!")) {
        lex();
        save_cmode = cmode; cmode = 0;            /* the operand is a VALUE */
        rvalue(unary());
        cmode = save_cmode;
        test_ax_z();
        if (cond_tail()) {                        /* !e false <=> e true: jump on NZ */
            emitjmp("JNZ", "L", clabel); cdone = 1; pk = 0;
        } else {
            materialize_z(1);                     /* !e = (e == 0) */
        }
        return mkty(0, 0, 0);
    }
    return factor();
}

/* word_op: emit MN for the two operands. place: 0 = __ax holds lhs, __t rhs;
   1 = __t holds lhs, __ax rhs. Result in __ax. */
int word_op(char *mn, int place, int commut) {
    if (place == 0 || commut) {
        emitstr("        "); emitstr(mn); line(" __ax,__t");
    } else {                                      /* SUBW: __ax = __t - __ax */
        emitstr("        "); emitstr(mn); line(" __t,__ax");
        line("        MOVW __ax,__t");
    }
    return 0;
}
int word_imm(char *mn, int k) {                   /* MN __ax,#k -- 16-bit Z afterwards */
    k = k & 65535;
    emitstr("        "); emitstr(mn); emitstr(" __ax,#"); emitdec(k); putchar(10);
    z16 = 1;
    return 0;
}

/* One binary-operator precedence level. level 1 | 2 ^ 3 & 4 == != 5 < > <= >=
   6 << >> 7 + - 8 * / %.  The pending-operand dance is described in the header. */
int binexpr(int level) {
    char op[3];
    char mn[8];
    int lty;
    int rty;
    int lk; int lv; int lg; int lo; int lb; int lp; char lname[64];
    int pushed;
    int place;                                    /* 0: lhs in __ax, rhs in __t/imm; 1: lhs in __t, rhs in __ax */
    int rimm;                                     /* rhs is a pending constant */
    int limm;                                     /* lhs is a pending constant (rhs in __ax) */
    int k;
    int scale;
    int want_c;
    int swapped;
    int helper;
    if (level > 8) return unary();
    lty = binexpr(level + 1);
    while (tok == T_PUNCT && oplevel(tname) == level) {
        strcpy_(op, tname); lex();
        lty = rvalue(lty);
        pushed = 0; lk = pk; rimm = 0; limm = 0; place = 0; k = 0;
        if (pk == 0) { if (peek_leaf(level) == 0) { push_val(); pushed = 1; } }
        else { lv = pval; lg = pglob; lo = poff; lb = pbase; lp = pptr; strcpy_(lname, pname); pk = 0; }
        rty = rvalue(binexpr(level + 1));
        helper = 0;
        if (level == 8 || level == 6) helper = 1; /* * / % << >>: JSR helpers, __t = lhs, __ax = rhs */
        /* ---- place the operands ---- */
        if (pushed) {                             /* stack = lhs, rhs pending/in __ax */
            flush_val(); pop_t(); place = 1;      /* __t = lhs, __ax = rhs */
        } else if (lk != 0 && pk != 0) {          /* both leaves */
            if (helper) {                         /* rhs -> __ax, lhs -> __t */
                flush_val();
                pend_set(lk, lv, lg, lo, lb, lp, lname); leaf_t(); place = 1;
            } else if (pk == 1) {                 /* rhs constant: lhs -> __ax, rhs immediate */
                rimm = 1; k = pval;
                pend_set(lk, lv, lg, lo, lb, lp, lname); flush_val(); place = 0;
            } else if (lk == 1) {                 /* lhs constant, rhs leaf: rhs -> __ax, lhs immediate */
                flush_val(); limm = 1; k = lv; place = 1;
            } else {                              /* rhs -> __t, lhs -> __ax */
                leaf_t();
                pend_set(lk, lv, lg, lo, lb, lp, lname); flush_val(); place = 0;
            }
        } else if (lk != 0) {                     /* lhs leaf, rhs in __ax */
            if (lk == 1 && helper == 0) { limm = 1; k = lv; place = 1; }
            else { pend_set(lk, lv, lg, lo, lb, lp, lname); leaf_t(); place = 1; }   /* __t = lhs */
        } else {                                  /* lhs in __ax, rhs leaf */
            if (helper) { line("        MOVW __t,__ax"); flush_val(); place = 1; }
            else if (pk == 1) { rimm = 1; k = pval; pk = 0; place = 0; }
            else { leaf_t(); place = 0; }
        }
        /* ---- emit ---- */
        if (helper) {                             /* __t = lhs, __ax = rhs */
            if (streq(op, "*")) { line("        JSR __mul"); use_mul = 1; }
            else if (streq(op, "/")) { line("        JSR __div"); use_div = 1; }
            else if (streq(op, "%")) { line("        JSR __mod"); use_mod = 1; }
            else if (streq(op, "<<")) { line("        JSR __shl"); use_shl = 1; }
            else { line("        JSR __shr"); use_shr = 1; }
            lty = mkty(0, 0, 0);
        } else if (level == 7) {                  /* + - with pointer scaling */
            scale = 1;
            if (ty_ptr(lty) > 0 && ty_ptr(rty) == 0) {            /* ptr +/- int: scale rhs */
                scale = elem_size(lty);
                if (scale == 2) {
                    if (rimm) k = k * 2;
                    else if (place == 0) scale2_t();
                    else scale2_ax();
                }
            } else if (streq(op, "+") && ty_ptr(rty) > 0 && ty_ptr(lty) == 0) {   /* int + ptr: scale lhs */
                scale = elem_size(rty);
                if (scale == 2) {
                    if (limm) k = k * 2;
                    else if (place == 1) scale2_t();
                    else scale2_ax();
                }
                lty = rty;
            } else {
                lty = mkty(0, 0, 0);
            }
            if (streq(op, "+")) {
                if (rimm || limm) { if ((k & 65535) == 1) line("        INCW __ax"); else if ((k & 65535) != 0) word_imm("ADDW", k); }
                else word_op("ADDW", place, 1);
            } else {
                if (rimm) { if ((k & 65535) == 1) line("        DECW __ax"); else if ((k & 65535) != 0) word_imm("SUBW", k); }
                else if (limm) {                  /* k - rhs: __ax = rhs */
                    line("        MOVW __t,__ax"); emitstr("        LDW __ax,#"); emitd(k); putchar(10);
                    line("        SUBW __ax,__t");
                }
                else word_op("SUBW", place, 0);
            }
            if (ty_ptr(lty) > 0 && ty_ptr(rty) > 0) lty = mkty(0, 0, 0);   /* ptr - ptr: bytes */
        } else if (level == 1 || level == 2 || level == 3) {
            if (level == 1) strcpy_(mn, "ORW");
            else if (level == 2) strcpy_(mn, "XORW");
            else strcpy_(mn, "ANDW");
            if (rimm || limm) word_imm(mn, k);
            else word_op(mn, place, 1);
            lty = mkty(0, 0, 0);
        } else if (level == 4) {                  /* == != : Z */
            if ((rimm || limm) && k == 0 && z16) { /* `(x & m) == 0`: Z is set already */ }
            else if (rimm || limm) { emitstr("        CMPW __ax,#"); emitd(k); putchar(10); }
            else { line("        JSR __cmp16"); use_cmp16 = 1; }
            if (cond_tail()) {                    /* jump when FALSE */
                if (streq(op, "==")) emitjmp("JNZ", "L", clabel); else emitjmp("JZ", "L", clabel);
                cdone = 1; pk = 0;
            } else {
                materialize_z(streq(op, "=="));
            }
            lty = mkty(0, 0, 0);
        } else {                                  /* level 5: < > <= >= -- C = (L >= R) */
            /* normalise: want truth = C (want_c=1) or !C (0), with L,R = lhs,rhs
               for < >= and swapped for > <= */
            swapped = 0;
            if (streq(op, ">") || streq(op, "<=")) swapped = 1;
            want_c = 0;
            if (streq(op, ">=") || streq(op, "<=")) want_c = 1;
            if (rimm) {                           /* __ax = lhs, constant rhs k */
                if (swapped) {                    /* lhs > k == lhs >= k+1 ; lhs <= k == !(lhs >= k+1) */
                    if ((k & 65535) == 65535) {   /* always false (>) / true (<=) */
                        if (want_c) line("        SEC"); else line("        CLC");
                        want_c = 1;
                    } else {
                        emitstr("        CMPW __ax,#"); emitd(k + 1); putchar(10);
                        want_c = 1 - want_c;
                    }
                } else {
                    emitstr("        CMPW __ax,#"); emitd(k); putchar(10);
                }
            } else if (limm) {                    /* constant lhs k, __ax = rhs */
                if (swapped) {                    /* k > rhs == rhs < k ; k <= rhs == rhs >= k */
                    emitstr("        CMPW __ax,#"); emitd(k); putchar(10);
                } else {                          /* k < rhs == rhs >= k+1 ; k >= rhs == !(rhs >= k+1) */
                    if ((k & 65535) == 65535) {
                        if (want_c) line("        SEC"); else line("        CLC");
                        want_c = 1;
                    } else {
                        emitstr("        CMPW __ax,#"); emitd(k + 1); putchar(10);
                        want_c = 1 - want_c;
                    }
                }
            } else if (place == 0) {              /* __ax = lhs, __t = rhs */
                if (swapped) line("        CMPW __t,__ax"); else line("        CMPW __ax,__t");
            } else {                              /* __t = lhs, __ax = rhs */
                if (swapped) line("        CMPW __ax,__t"); else line("        CMPW __t,__ax");
            }
            if (cond_tail()) {                    /* jump when FALSE: C != want_c */
                if (want_c) emitjmp("JNC", "L", clabel); else emitjmp("JC", "L", clabel);
                cdone = 1; pk = 0;
            } else {
                materialize_c(want_c);
            }
            lty = mkty(0, 0, 0);
        }
        pk = 0;                                   /* the result is in __ax (or branched) */
    }
    return lty;
}

int logand() {
    int lf;
    int le;
    int ty;
    int outer;
    ty = binexpr(1);
    if (is_punct("&&") == 0) return ty;
    if (cmode) {                                  /* jump-if-false chain to clabel */
        while (is_punct("&&")) {
            lex();
            if (cdone == 0) { rvalue(ty); test_ax_z(); emitjmp("JZ", "L", clabel); }
            cdone = 0;
            ty = binexpr(1);
        }
        return ty;                                /* (cdone tells the caller about the last one) */
    }
    lf = newlabel(); le = newlabel();             /* as a VALUE: operands in cond mode */
    rvalue(ty); test_ax_z(); emitjmp("JZ", "L", lf);
    outer = clabel; cmode = 1; clabel = lf;
    while (is_punct("&&")) {
        lex(); cdone = 0;
        ty = binexpr(1);
        if (cdone == 0) { rvalue(ty); test_ax_z(); emitjmp("JZ", "L", lf); }
    }
    cmode = 0; clabel = outer; cdone = 0;
    line("        LDW __ax,#1"); emitjmp("JMP.A", "L", le);
    emitlabel("L", lf); line("        LDW __ax,#0"); emitlabel("L", le);
    pk = 0;
    return mkty(0, 0, 0);
}

int logor() {
    int lt;
    int le;
    int ty;
    ty = logand();
    if (is_punct("||") == 0) return ty;
    lt = newlabel(); le = newlabel();             /* always a VALUE (cond mode pre-scans for ||) */
    rvalue(ty); test_ax_z(); emitjmp("JNZ", "L", lt);
    while (is_punct("||")) {
        lex();
        rvalue(logand()); test_ax_z(); emitjmp("JNZ", "L", lt);
    }
    line("        LDW __ax,#0"); emitjmp("JMP.A", "L", le);
    emitlabel("L", lt); line("        LDW __ax,#1"); emitlabel("L", le);
    pk = 0;
    return mkty(0, 0, 0);
}

/* store_pending_var: the pending descriptor (saved in the l* args) names the
   variable; the value is in __ax (or pending constant kk when isk). */
int store_var(int lg, int lo, int lb, int lp, char *lname, int isk, int kk, int top) {
    int sz;
    int d;
    sz = type_size(lb, lp);
    if (lg) {
        if (sz == 2) {
            if (isk && top) { emitstr("        LDW _g_"); emitstr(lname); emitstr(",#"); emitd(kk); putchar(10); return 0; }
            if (isk) { emitstr("        LDW __ax,#"); emitd(kk); putchar(10); }
            emitstr("        MOVW _g_"); emitstr(lname); line(",__ax");
        } else {
            if (isk) {
                if (top == 0) { emitstr("        LDW __ax,#"); emitd(kk & 255); putchar(10); }
                emitstr("        LDA #"); emitdec(kk & 255); putchar(10);
            } else line("        LDA __ax");
            emitstr("        STA _g_"); emitstr(lname); putchar(10);
        }
        return 0;
    }
    d = dsp(lo);
    if (sz == 2) {
        if (isk) { emitstr("        LDW __ax,#"); emitd(kk); putchar(10); }
        st_local_word(d);
    } else {                                      /* char slot: byte + zero high */
        if (isk) {
            if (top == 0) { emitstr("        LDW __ax,#"); emitd(kk & 255); putchar(10); }
            emitstr("        LDA #"); emitdec(kk & 255); putchar(10);
        } else line("        LDA __ax");
        st_local_byte(d);
    }
    return 0;
}

/* inplace_update: `g = g +/- k` on a GLOBAL word (lhs pending in the l* args,
   tok just past '='): peek ID op NUM then ; or ) -> INCW/DECW/ADDW/SUBW in place.
   Returns 1 and consumes the tokens when it applied. */
int inplace_update(char *lname, int lb, int lp, int top) {
    int ok;
    int neg;
    int k;
    int esz;
    ok = 0;
    lex_save();
    if (tok == T_ID && streq(tname, lname)) {
        lex();
        if (is_punct("+") || is_punct("-")) {
            neg = is_punct("-");
            lex();
            if (tok == T_NUM) {
                k = tval; lex();
                if (is_punct(";") || is_punct(")")) ok = 1;
            }
        }
    }
    if (ok == 0) { lex_restore(); return 0; }
    /* tok is now the ';' / ')' -- consumed by the caller's eat() as usual */
    esz = 1;
    if (lp > 0) esz = type_size(lb, lp - 1);
    k = (k * esz) & 65535;
    if (neg) k = (0 - k) & 65535;
    if (k == 1) { emitstr("        INCW _g_"); emitstr(lname); putchar(10); }
    else if (k == 65535) { emitstr("        DECW _g_"); emitstr(lname); putchar(10); }
    else if (k < 32768) { emitstr("        ADDW _g_"); emitstr(lname); emitstr(",#"); emitd(k); putchar(10); }
    else { emitstr("        SUBW _g_"); emitstr(lname); emitstr(",#"); emitd((0 - k) & 65535); putchar(10); }
    if (top == 0) { emitstr("        MOVW __ax,_g_"); emitstr(lname); putchar(10); }
    return 1;
}

int expr() {                          /* assignment (right-associative) */
    int lty;
    int top;
    int save_cmode;
    int lk; int lg; int lo; int lb; int lp; char lname[64];
    top = stmt_expr; stmt_expr = 0;   /* only the outermost expression of a statement */
    lty = logor();
    if (is_punct("=")) {
        lex();
        if (ty_lval(lty) == 0) line("; ERROR: assignment to a non-lvalue");
        if (pk == 2) {                            /* a named variable */
            lk = pk; lg = pglob; lo = poff; lb = pbase; lp = pptr; strcpy_(lname, pname); pk = 0;
            if (lg && type_size(lb, lp) == 2 && inplace_update(lname, lb, lp, top)) {
                pk = 0; return mkty(ty_base(lty), ty_ptr(lty), 0);
            }
            save_cmode = cmode; cmode = 0;
            rvalue(expr());                       /* the value: pending or in __ax */
            cmode = save_cmode;
            if (pk == 1) { store_var(lg, lo, lb, lp, lname, 1, pval, top); pk = 0; }
            else { flush_val(); store_var(lg, lo, lb, lp, lname, 0, 0, top); }
            return mkty(ty_base(lty), ty_ptr(lty), 0);
        }
        flush_addr();                             /* a computed lvalue: address in __ax */
        push_val();
        save_cmode = cmode; cmode = 0;
        rvalue(expr()); flush_val();
        cmode = save_cmode;
        pop_t();                                  /* __t = address */
        line("        LPW1 __t");
        if (ty_size(lty) == 2) {
            line("        LDA __ax"); line("        STA (P1)+");
            line("        LDA __ax+1"); line("        STA (P1)");
        } else {
            line("        LDA __ax"); line("        STA (P1)");
        }
        return mkty(ty_base(lty), ty_ptr(lty), 0);
    }
    return lty;
}

/* --- statements --------------------------------------------------------------- */
int block() {
    eat("{");
    while (is_punct("}") == 0 && tok != T_EOF) stmt();
    eat("}");
    return 0;
}

/* cond_expr: parse a condition and arrange a jump to label `lab` when it is
   FALSE. `untilsemi`: the condition ends at ';' (for) rather than ')'. */
int cond_expr(int lab, int untilsemi) {
    int ty;
    if (cond_has_or(untilsemi)) {                 /* || at the top: value mode */
        cmode = 0;
        ty = rvalue(expr()); test_ax_z();
        emitjmp("JZ", "L", lab);
        pk = 0;
        return 0;
    }
    cmode = 1; clabel = lab; cdone = 0;
    ty = expr();
    cmode = 0;
    if (cdone == 0) { rvalue(ty); test_ax_z(); emitjmp("JZ", "L", lab); }
    cdone = 0; pk = 0;
    return 0;
}

int stmt() {
    int l1;
    int l2;
    int l3;
    int l4;
    cursp = 0;
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
        if (cnt == 0 && sz == 1) sz = 2;          /* a char scalar owns a zero-high 2-byte slot */
        off = pre_lookup(dn);
        if (off < 0) { toobig("local_not_in_prescan"); off = 1; }
        else off = pre_foff[off];
        if (lookup(dn) == 0 || look_isglobal) addvar(dn, off, base, g_ptr, cnt);   /* first decl wins */
        if (cnt == 0 && is_punct("=")) {
            lex(); rvalue(expr());
            if (pk == 1) { store_var(0, off, base, g_ptr, dn, 1, pval, 1); pk = 0; }
            else { flush_val(); store_var(0, off, base, g_ptr, dn, 0, 0, 1); }
        }
        eat(";");
        return 0;
    }
    if (tok == T_KW && streq(tname, "return")) {
        lex();
        if (is_punct(";") == 0) { rvalue(expr()); flush_val(); }
        eat(";");
        emitstr("        JMP.A _ret_"); emitstr(curfunc); putchar(10);
        return 0;
    }
    if (tok == T_KW && streq(tname, "if")) {
        lex(); eat("(");
        l1 = newlabel(); l2 = newlabel();
        cond_expr(l1, 0); eat(")");               /* false -> else/end */
        stmt();
        if (tok == T_KW && streq(tname, "else")) {
            emitjmp("JMP.A", "L", l2);
            emitlabel("L", l1);
            lex();
            stmt();
            emitlabel("L", l2);
        } else {
            emitlabel("L", l1);
        }
        return 0;
    }
    if (tok == T_KW && streq(tname, "while")) {
        l1 = newlabel(); l2 = newlabel();         /* top, end */
        lex();
        emitlabel("L", l1);
        eat("("); cond_expr(l2, 0); eat(")");
        stmt();
        emitjmp("JMP.A", "L", l1);
        emitlabel("L", l2);
        return 0;
    }
    if (tok == T_KW && streq(tname, "for")) {
        /* layout: init; top: cond?JZ end; JMP body; post: post; JMP top;
           body: BODY; JMP post; end:   (emits post before body, runtime loops) */
        lex(); eat("(");
        if (is_punct(";") == 0) { stmt_expr = 1; expr(); }
        eat(";");
        l1 = newlabel(); l2 = newlabel(); l3 = newlabel(); l4 = newlabel();
        emitlabel("L", l1);
        if (is_punct(";") == 0) cond_expr(l4, 1);
        eat(";");
        emitjmp("JMP.A", "L", l3);
        emitlabel("L", l2);
        if (is_punct(")") == 0) { stmt_expr = 1; expr(); }
        eat(")");
        emitjmp("JMP.A", "L", l1);
        emitlabel("L", l3);
        stmt();
        emitjmp("JMP.A", "L", l2);
        emitlabel("L", l4);
        return 0;
    }
    if (is_punct(";")) { lex(); return 0; }
    stmt_expr = 1;
    expr();
    pk = 0;
    eat(";");
    return 0;
}

/* --- global initializers: {lists} and strings -------------------------------- */
int gil_kind[8192];   /* 0 = number, 1 = string-literal index */
int gil_val[8192];
int gil_n = 0;        /* items used */
int gil_cnt[512];     /* per global (hasi == 3): number of items */
int intern_str() {    /* the current T_STR token -> string index in the pool */
    int k;
    int j;
    if (scount >= 2048 || spooln + tstrlen >= 32768) {
        if (scount >= 2048) toobig("strings_2048"); else toobig("spool_32768");
        return 0;
    }
    k = scount; scount = scount + 1;
    soff[k] = spooln; slen[k] = tstrlen;
    j = 0;
    while (j < tstrlen) { spool[spooln] = tstr[j]; spooln = spooln + 1; j = j + 1; }
    return k;
}

/* --- emit all used runtime helpers + the data section ------------------------- */
int emit_runtime() {
    if (use_mul) emit_mul();
    if (use_div || use_mod) emit_divmod();
    if (use_div) emit_div();
    if (use_mod) emit_mod();
    if (use_shl) emit_shl();
    if (use_shr) emit_shr();
    if (use_cmp16) emit_cmp16();
    line("__ax:   .fill 2");
    line("__t:    .fill 2");
    line("__c:    .fill 1");
    line("__sp0:  .fill 2");
    if (use_la) line("__la:   .fill 2");
    if (use_mul) line("__r:    .fill 2");
    if (use_mul || use_div || use_mod || use_shl || use_shr) line("__n:    .fill 1");
    if (use_div || use_mod) line("__dr:   .fill 2");
    return 0;
}

int emit_globals() {
    int i;
    int j;
    int e;
    int m;
    i = 0;
    while (i < gcount) {
        emitstr("_g_"); emitstr(gpool + goff[i]);
        if (ghas[i] == 3) {                           /* {list}: one .word/.byte per item, zero tail */
            int esz;
            esz = type_size(gbase[i], gptr[i]);
            emitstr(":"); putchar(10);
            j = gini[i]; e = gini[i] + gil_cnt[i]; m = 0;
            while (j < e) {
                if (gil_kind[j]) { emitstr("        .word __s"); emitdec(gil_val[j]); }
                else if (esz == 2) { emitstr("        .word "); emitdec(gil_val[j]); }
                else { emitstr("        .byte "); emitdec(gil_val[j] & 255); }
                putchar(10);
                j = j + 1; m = m + 1;
            }
            if (gcnt[i] > m) { emitstr("        .fill "); emitdec((gcnt[i] - m) * esz); putchar(10); }
        } else if (ghas[i] == 4) {                    /* char s[N] = "...": bytes, zero-padded */
            emitstr(":"); putchar(10);
            j = soff[gini[i]]; e = soff[gini[i]] + slen[gini[i]]; m = 0;
            emitstr("        .byte ");
            while (j < e && m < gcnt[i]) { if (m > 0) putchar(44); emitdec(spool[j] & 255); j = j + 1; m = m + 1; }
            if (m == 0) emitstr("0");
            putchar(10);
            if (gcnt[i] > m) { emitstr("        .fill "); emitdec(gcnt[i] - m); putchar(10); }
        } else if (ghas[i] == 2) {                    /* char *p = "..." */
            emitstr(":   .word __s"); emitdec(gini[i]); putchar(10);
        } else if (gcnt[i] > 0) {
            emitstr(":   .fill ");
            emitdec(gcnt[i] * type_size(gbase[i], gptr[i])); putchar(10);
        } else if (gbase[i] >= 2 && gptr[i] == 0) {   /* struct/union scalar */
            emitstr(":   .fill "); emitdec(type_size(gbase[i], 0)); putchar(10);
        } else if (ghas[i]) {
            if (type_size(gbase[i], gptr[i]) == 1) { emitstr(":   .byte "); emitdec(gini[i] & 255); }
            else { emitstr(":   .word "); emitdec(gini[i] & 65535); }
            putchar(10);
        } else {
            emitstr(":   .fill "); emitdec(type_size(gbase[i], gptr[i])); putchar(10);
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

/* body_uses: does the body (positioned at its '{') name identifier `nm`? Rewinds. */
int body_uses(char *nm) {
    int save;
    int depth;
    int found;
    save = spos;
    depth = 1; found = 0;
    while (depth > 0 && tok != T_EOF) {
        lex();
        if (is_punct("{")) depth = depth + 1;
        else if (is_punct("}")) depth = depth - 1;
        else if (tok == T_ID && streq(tname, nm)) found = 1;
    }
    spos = save;
    tok = T_PUNCT; tname[0] = 123; tname[1] = 0;
    return found;
}

int st_intern(char *s) {
    int o;
    o = stpooln;
    while (*s != 0) {
        if (stpooln >= 2047) { toobig("stpool_2048"); return o; }
        stpool[stpooln] = *s; stpooln = stpooln + 1; s = s + 1;
    }
    stpool[stpooln] = 0; stpooln = stpooln + 1;
    return o;
}
int m_intern(char *s) {
    int o;
    o = mpooln;
    while (*s != 0) {
        if (mpooln >= 8191) { toobig("mpool_8192"); return o; }
        mpool[mpooln] = *s; mpooln = mpooln + 1; s = s + 1;
    }
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
    if (stcount >= 128) { toobig("structs_128"); return 0; }  /* stnoff/stsz/... [128] */
    stnoff[stcount] = st_intern(tag);
    stfirst[stcount] = mtotal;
    eat("{");
    off = 0; sz = 0;
    while (is_punct("}") == 0 && tok != T_EOF && mtotal < 1024) {
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
    if (mtotal >= 1024) toobig("members_1024__across_all_structs");
    eat("}"); eat(";");
    if (isunion) stsz[stcount] = sz;
    else stsz[stcount] = off;
    stnm[stcount] = mtotal - stfirst[stcount];
    stcount = stcount + 1;
    return 0;
}

int adj_p3(int n, int up) {                      /* ADDP3/SUBP3 #n in imm8 chunks */
    int k;
    while (n > 0) {
        k = n;
        if (k > 255) k = 255;
        n = n - k;
        if (up) emitstr("        ADDP3 #"); else emitstr("        SUBP3 #");
        emitdec(k); putchar(10);
    }
    return 0;
}

/* --- top-level declarations: functions (with params) and global vars --------- */
int toplevel() {
    char nm[64];
    char pn[64];
    char lastp[64];
    int hasi;
    int v;
    int pcount;
    int i;
    int nl;
    int rptr;
    int pbas;
    int gbas;
    int lastused;
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
        vcount = 0; vpooln = 0; nlocoff = 1;     /* fresh scope; locals from P3+1 */
        pcount = 0;
        if (is_punct(")") == 0) {
            pbas = parse_type();
            strcpy_(pn, tname); lex();
            addvar(pn, 0, pbas, g_ptr, 0);
            pcount = 1;
            while (is_punct(",")) {
                lex();
                pbas = parse_type();
                strcpy_(pn, tname); lex();
                addvar(pn, 0, pbas, g_ptr, 0);
                pcount = pcount + 1;
            }
        }
        eat(")");
        addfunc(nm, gbas, rptr);                 /* return type, for callers */
        if (is_punct(";")) { lex(); return 0; }  /* a prototype: no body */

        strcpy_(curfunc, nm);
        /* Frame: the LAST parameter arrives in __ax and gets the first local slot
           (P3+1) when the body names it; the other parameters were pushed left to
           right, so param i (i < n-1) sits above the return address at
           L+3+2*(n-2-i). Locals follow in declaration order. */
        lastused = 0;
        if (pcount > 0) {
            strcpy_(lastp, vpool + vnoff[pcount - 1]);
            if (body_uses(lastp)) { lastused = 1; vfoff[pcount - 1] = 1; nlocoff = 3; }
        }
        nl = count_locals(nlocoff);              /* local bytes; slots pre-assigned */
        framel = nlocoff - 1 + nl;
        i = 0;
        while (i < pcount - 1) { vfoff[i] = framel + 3 + 2 * (pcount - 2 - i); i = i + 1; }
        emitstr("_f_"); emitstr(nm); line(":");
        cursp = 0;
        if (framel > 0) adj_p3(framel, 0);       /* SUBP3 #L reserves the locals */
        if (lastused) line("        STW (P3+1),__ax");
        i = 0;                                   /* char params: keep the slot's high byte 0 */
        while (i < pcount) {
            if (type_size(vbase[i], vptr[i]) == 1) {
                if (i < pcount - 1 || lastused) {
                    line("        LDA #0");
                    emitstr("        STA "); emit_p3(vfoff[i] + 1); putchar(10);
                }
            }
            i = i + 1;
        }
        block();
        emitstr("_ret_"); emitstr(nm); line(":");
        if (framel > 0) adj_p3(framel, 1);       /* ADDP3 #L frees them */
        line("        RTS");
        return 0;
    }
    hasi = 0; v = 0;                             /* global variable */
    pcount = 0;                                  /* reuse as array count; -1 = [] to infer */
    if (is_punct("[")) {
        lex();
        if (is_punct("]")) pcount = 0 - 1; else { pcount = tval; lex(); }
        eat("]");
    }
    if (is_punct("=")) {
        lex();
        if (is_punct("{")) {                     /* {item, item, ...}: numbers or strings */
            lex();
            hasi = 3; v = gil_n;                 /* v = first item's index in the item pool */
            i = 0;
            while (is_punct("}") == 0 && tok != T_EOF) {
                if (gil_n >= 8192) { toobig("initializer_items_8192"); return 0; }
                if (tok == T_STR) { gil_kind[gil_n] = 1; gil_val[gil_n] = intern_str(); lex(); }
                else if (is_punct("-")) { lex(); gil_kind[gil_n] = 0; gil_val[gil_n] = (0 - tval) & 65535; lex(); }
                else { gil_kind[gil_n] = 0; gil_val[gil_n] = tval & 65535; lex(); }
                gil_n = gil_n + 1; i = i + 1;
                if (is_punct(",")) lex();
            }
            eat("}");
            if (pcount < 0) pcount = i;          /* [] : the item count */
            if (pcount == 0) pcount = i;         /* (a scalar with a brace list: treat as array) */
        } else if (tok == T_STR) {               /* "..." : char* pointer, or char[] bytes */
            if (rptr == 0 && gbas == 1) {        /* char s[] = "..." -> the bytes + NUL */
                hasi = 4; v = intern_str();
                if (pcount < 0) pcount = tstrlen + 1;
            } else { hasi = 2; v = intern_str(); }
            lex();
        } else {
            if (is_punct("-")) { lex(); v = 0 - tval; }
            else v = tval;
            lex();
            hasi = 1;
        }
    }
    if (pcount < 0) pcount = 0;
    eat(";");
    addglobal(nm, gbas, rptr, pcount, hasi, v);
    if (hasi == 3) gil_cnt[gcount - 1] = i;
    return 0;
}

/* --- driver: compile one `int main() { ... }` to a runnable program ------------ */
int main() {
    slurp();
    lex();                                       /* prime the first token */

    /* Startup (mirrors p8cc.py): keep the caller's P3 in __sp0; run on a stack
       growing down from CSTACKTOP ($F800) unless the inherited P3 is already
       below it (a nested launch keeps its stack); restore and RTS. */
    line("        .relax");
    line("        .org $6A00");   /* = TPABASE (gen_memmap.py); this subset twin emits it as
                                    a literal (no #include; kept in sync with p8cc.py by hand) */
    line("        TPA3L"); line("        STA __sp0"); line("        TPA3H"); line("        STA __sp0+1");
    line("        LDB #248"); line("        CMP");
    line("        JNC __sk0");
    line("        LDP3 #63487");                 /* $F7FF = CSTACKTOP-1 */
    line("__sk0:  JSR _f_main");
    line("        LPW3 __sp0"); line("        RTS");

    while (tok != T_EOF) toplevel();

    emit_runtime();
    emit_globals();
    return 0;
}
