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
 * before use (gcc needs no implicit declarations), only getchar/putchar/puts
 * for I/O.  EOF is c==0 (P8X CONIN at end of stdin) or c==-1 (host getchar).
 *
 * Built incrementally; this stage is the lexer plus a single-pass parser/code-
 * generator for a first language slice: one `int main()`, integer arithmetic
 * (+ -), parentheses, putchar(e), return, and statements (block/if-free).  This
 * establishes the full emit pipeline (startup, function, runtime helpers, data)
 * and the host-vs-p8cc.py differential harness; the language grows from here.
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
char src[4096];      /* whole source, NUL-terminated (Milestone B: stream this) */
int srclen = 0;
int spos = 0;        /* scan cursor */
int tok = 0;         /* current token kind */
int tval = 0;        /* numeric value when tok == T_NUM */
char tname[64];      /* identifier / keyword / punctuation text */

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
int slurp() {
    int c;
    int n;
    n = 0;
    c = getchar();
    while (c != 0 && c != -1) {
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

    /* string literal (content scanned past; pooling comes with the parser) */
    if (c == 34) {                                          /* " */
        spos = spos + 1;
        while (src[spos] != 34 && src[spos] != 0) {
            if (src[spos] == 92) spos = spos + 1;           /* skip escaped char */
            spos = spos + 1;
        }
        if (src[spos] == 34) spos = spos + 1;
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
int use_add = 0;
int use_sub = 0;

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

int is_punct(char *p) { return tok == T_PUNCT && streq(tname, p); }

int eat(char *p) {
    if (is_punct(p) == 0) { emitstr("; ERROR: expected "); line(p); }
    lex();
    return 0;
}

/* ---- codegen primitives (result of an expression lives in __ax) ----------- */
int set_ax(int v) {                  /* __ax = constant v */
    emitstr("        LDA #"); emitdec(v & 255); putchar(10);
    line("        STA __ax");
    emitstr("        LDA #"); emitdec((v >> 8) & 255); putchar(10);
    line("        STA __ax+1");
    return 0;
}

int push_ax() {                      /* push __ax onto the P3 hardware stack */
    line("        LDA __ax"); line("        PHA");
    line("        LDA __ax+1"); line("        PHA");
    return 0;
}

int pop_t() {                        /* pop into __t */
    line("        PLA"); line("        STA __t+1");
    line("        PLA"); line("        STA __t");
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

/* ---- expressions / statements (mutually recursive -> forward decls) -------- */
int expr();
int stmt();

int primary() {
    char nm[64];
    if (tok == T_NUM) { set_ax(tval); lex(); return 0; }
    if (is_punct("(")) { lex(); expr(); eat(")"); return 0; }
    if (tok == T_ID) {
        strcpy_(nm, tname); lex(); eat("(");
        expr();                                  /* the single argument */
        eat(")");
        if (streq(nm, "putchar")) {
            line("        LDA __ax"); line("        JSR $0103");
        }
        return 0;
    }
    line("; ERROR: bad primary");
    return 0;
}

int expr() {                          /* primary (('+'|'-') primary)* */
    int op;
    primary();
    while (is_punct("+") || is_punct("-")) {
        op = tname[0];                           /* '+' = 43, '-' = 45 */
        lex();
        push_ax();
        primary();
        pop_t();
        if (op == 43) { line("        JSR __add"); use_add = 1; }
        else { line("        JSR __sub"); use_sub = 1; }
    }
    return 0;
}

int block() {
    eat("{");
    while (is_punct("}") == 0 && tok != T_EOF) stmt();
    eat("}");
    return 0;
}

int stmt() {
    if (is_punct("{")) { block(); return 0; }
    if (tok == T_KW && streq(tname, "return")) {
        lex();
        if (is_punct(";") == 0) expr();
        eat(";");
        line("        RTS");
        return 0;
    }
    if (is_punct(";")) { lex(); return 0; }
    expr();
    eat(";");
    return 0;
}

/* ---- driver: compile one `int main() { ... }` to a runnable program -------- */
int main() {
    slurp();
    lex();                                       /* prime the first token */

    line("        .org $B000");
    line("        JSR _f_main");
    line("        RTS");

    if (tok == T_KW) lex();                      /* return type 'int' */
    if (tok == T_ID) lex();                      /* function name (main) */
    eat("(");
    eat(")");
    line("_f_main:");
    block();
    line("        RTS");                          /* fall-through return */

    if (use_add) emit_add();
    if (use_sub) emit_sub();
    line("__ax:   .fill 2");
    line("__t:    .fill 2");
    line("__c:    .fill 1");
    return 0;
}
