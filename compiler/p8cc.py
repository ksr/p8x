#!/usr/bin/env python3
"""p8cc - a tiny C cross-compiler for the P8X.

Emits P8X assembly (for assembler/p8xasm.py) targeting the OS transient program
area ($B000), so the output is a RUNnable program. This is v0.1: a deliberately
small subset, grown in phases (params/locals, pointers/arrays, div/mod, libc).

Supported now:
  types        int (16-bit), char (8-bit)
  top level    function definitions (no parameters yet), global var decls
  statements   { }  decl  if/else  while  return [e];  expr;  ;
  expressions  =  == != < > <= >=  + -  *  unary - !  calls  ( )
               primaries: int/char/string literal, identifier, call
  builtins     putchar(e)   puts(e)        (over the BIOS at $0103 / $0112)

Execution model: a 16-bit pseudo-accumulator AX (memory word __ax) holds every
expression result; the hardware stack (P3) holds temporaries (PHA/PLA) and call
return addresses (JSR/RTS). Binary operators are runtime helper calls so the
generated code stays compact. v0.1 gives every variable static storage (no
frame yet), so there is no recursion or reentrancy — that arrives with the
calling-convention phase.

Usage:  p8cc.py prog.c [-o prog.asm]
Then:   p8xasm.py prog.asm -o prog.bin --base 0xB000
"""
import sys, re

# --------------------------------------------------------------------------- #
# Lexer
# --------------------------------------------------------------------------- #
KEYWORDS = {"int", "char", "void", "if", "else", "while", "return"}
# 3-char then 2-char then 1-char punctuators (longest match first)
PUNCT = ["==", "!=", "<=", ">=", "&&", "||",
         "{", "}", "(", ")", ";", ",", "=", "+", "-", "*", "<", ">", "!"]


def lex(src):
    toks, i, n, line = [], 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1; i += 1; continue
        if c in " \t\r":
            i += 1; continue
        if src.startswith("//", i):
            i = src.find("\n", i); i = n if i < 0 else i; continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        if c.isalpha() or c == "_":
            j = i + 1
            while j < n and (src[j].isalnum() or src[j] == "_"): j += 1
            w = src[i:j]
            toks.append(("kw" if w in KEYWORDS else "id", w, line)); i = j; continue
        if c.isdigit():
            j = i + 1
            if c == "0" and i + 1 < n and src[i + 1] in "xX":
                j = i + 2
                while j < n and src[j] in "0123456789abcdefABCDEF": j += 1
                toks.append(("num", int(src[i:j], 16), line)); i = j; continue
            while j < n and src[j].isdigit(): j += 1
            toks.append(("num", int(src[i:j]), line)); i = j; continue
        if c == "'":
            # char literal with minimal escapes
            if src[i + 1] == "\\":
                esc = {"n": 10, "r": 13, "t": 9, "0": 0, "\\": 92, "'": 39}
                toks.append(("num", esc[src[i + 2]], line)); i += 4; continue
            toks.append(("num", ord(src[i + 1]), line)); i += 3; continue
        if c == '"':
            j, buf = i + 1, []
            while j < n and src[j] != '"':
                if src[j] == "\\":
                    esc = {"n": 10, "r": 13, "t": 9, "0": 0, "\\": 92, '"': 34}
                    buf.append(esc[src[j + 1]]); j += 2
                else:
                    buf.append(ord(src[j])); j += 1
            toks.append(("str", buf, line)); i = j + 1; continue
        for p in PUNCT:
            if src.startswith(p, i):
                toks.append(("op", p, line)); i += len(p); break
        else:
            sys.exit("p8cc: line %d: bad character %r" % (line, c))
    toks.append(("eof", None, line))
    return toks


# --------------------------------------------------------------------------- #
# Parser -> AST (tuples)
# --------------------------------------------------------------------------- #
class P:
    def __init__(self, toks): self.t = toks; self.i = 0
    def peek(self): return self.t[self.i]
    def kind(self): return self.t[self.i][0]
    def val(self): return self.t[self.i][1]
    def line(self): return self.t[self.i][2]
    def next(self): tok = self.t[self.i]; self.i += 1; return tok
    def err(self, m): sys.exit("p8cc: line %d: %s" % (self.line(), m))
    def eat(self, v):
        k, val, _ = self.t[self.i]
        if val != v: self.err("expected %r, got %r" % (v, val))
        self.i += 1
    def accept(self, v):
        if self.t[self.i][1] == v: self.i += 1; return True
        return False

    def program(self):
        decls = []
        while self.kind() != "eof":
            decls.append(self.toplevel())
        return decls

    def typespec(self):
        if self.val() in ("int", "char", "void"):
            return self.next()[1]
        self.err("expected a type")

    def toplevel(self):
        ty = self.typespec()
        name = self.next()
        if name[0] != "id": self.err("expected name")
        name = name[1]
        if self.accept("("):
            self.eat(")")                 # v0.1: no parameters
            body = self.block()
            return ("func", ty, name, body)
        # global variable
        init = None
        if self.accept("="):
            init = self.expr()
        self.eat(";")
        return ("gvar", ty, name, init)

    def block(self):
        self.eat("{")
        stmts = []
        while self.val() != "}":
            stmts.append(self.stmt())
        self.eat("}")
        return ("block", stmts)

    def stmt(self):
        v = self.val()
        if v == "{": return self.block()
        if v in ("int", "char"):
            ty = self.next()[1]; name = self.next()[1]; init = None
            if self.accept("="): init = self.expr()
            self.eat(";")
            return ("decl", ty, name, init)
        if v == "if":
            self.next(); self.eat("("); c = self.expr(); self.eat(")")
            then = self.stmt(); els = self.stmt() if self.accept("else") else None
            return ("if", c, then, els)
        if v == "while":
            self.next(); self.eat("("); c = self.expr(); self.eat(")")
            return ("while", c, self.stmt())
        if v == "return":
            self.next()
            e = None if self.val() == ";" else self.expr()
            self.eat(";"); return ("return", e)
        if v == ";":
            self.next(); return ("empty",)
        e = self.expr(); self.eat(";"); return ("expr", e)

    # precedence-climbing expression parser
    def expr(self): return self.assign()

    def assign(self):
        left = self.binary(0)
        if self.val() == "=":
            self.next()
            return ("assign", left, self.assign())
        return left

    # binary operator precedence tables
    LEVELS = [["==", "!="], ["<", ">", "<=", ">="], ["+", "-"], ["*"]]

    def binary(self, lvl):
        if lvl >= len(self.LEVELS): return self.unary()
        left = self.binary(lvl + 1)
        while self.val() in self.LEVELS[lvl]:
            op = self.next()[1]
            right = self.binary(lvl + 1)
            left = ("bin", op, left, right)
        return left

    def unary(self):
        if self.val() in ("-", "!"):
            op = self.next()[1]
            return ("unary", op, self.unary())
        return self.postfix()

    def postfix(self):
        e = self.primary()
        while self.val() == "(":            # call
            self.next()
            args = []
            if self.val() != ")":
                args.append(self.expr())
                while self.accept(","): args.append(self.expr())
            self.eat(")")
            if e[0] != "id": self.err("call of non-function")
            e = ("call", e[1], args)
        return e

    def primary(self):
        k, v, _ = self.peek()
        if k == "num": self.next(); return ("num", v)
        if k == "str": self.next(); return ("str", v)
        if k == "id":  self.next(); return ("id", v)
        if v == "(":
            self.next(); e = self.expr(); self.eat(")"); return e
        self.err("unexpected %r" % (v,))


# --------------------------------------------------------------------------- #
# Code generator
# --------------------------------------------------------------------------- #
class Gen:
    def __init__(self):
        self.code = []; self.data = []
        self.globals = {}     # name -> (label, type)
        self.locals = {}      # name -> (label, type)  (static storage, v0.1)
        self.strings = {}     # tuple(bytes) -> label
        self.used = set()     # runtime helpers referenced
        self.nl = 0           # label counter
        self.func = None

    def lbl(self, base="L"):
        self.nl += 1; return "%s%d" % (base, self.nl)

    def emit(self, *lines): self.code.extend(lines)

    def need(self, h): self.used.add(h)

    # ---- variable resolution ------------------------------------------------
    def declare(self, name, ty, scope):
        lab = ("_g_" + name) if scope == "g" else ("_v_%s_%s" % (self.func, name))
        (self.globals if scope == "g" else self.locals)[name] = (lab, ty)
        self.data.append("%s:    .fill %d" % (lab, 2 if ty == "int" else 1))
        return lab

    def resolve(self, name):
        if name in self.locals: return self.locals[name]
        if name in self.globals: return self.globals[name]
        sys.exit("p8cc: undeclared identifier %r" % name)

    def string(self, bs):
        key = tuple(bs)
        if key not in self.strings:
            lab = self.lbl("__s")
            self.strings[key] = lab
            body = ",".join(str(b) for b in bs)
            self.data.append("%s:    .byte %s,0" % (lab, body) if bs
                             else "%s:    .byte 0" % lab)
        return self.strings[key]

    # ---- expression -> result in __ax --------------------------------------
    def push_ax(self): self.emit("        LDA __ax", "        PHA",
                                  "        LDA __ax+1", "        PHA")
    def pop_t(self): self.emit("        PLA", "        STA __t+1",
                               "        PLA", "        STA __t")

    def set_ax_const(self, v):
        v &= 0xFFFF
        self.emit("        LDA #%d" % (v & 0xFF), "        STA __ax",
                  "        LDA #%d" % (v >> 8), "        STA __ax+1")

    def load_var(self, name):
        lab, ty = self.resolve(name)
        self.emit("        LDA %s" % lab, "        STA __ax")
        if ty == "int":
            self.emit("        LDA %s+1" % lab, "        STA __ax+1")
        else:
            self.emit("        LDA #0", "        STA __ax+1")

    def store_var(self, name):                  # __ax -> var
        lab, ty = self.resolve(name)
        self.emit("        LDA __ax", "        STA %s" % lab)
        if ty == "int":
            self.emit("        LDA __ax+1", "        STA %s+1" % lab)

    def gen_expr(self, e):
        kind = e[0]
        if kind == "num":
            self.set_ax_const(e[1])
        elif kind == "str":
            lab = self.string(e[1])
            self.emit("        LDA #<%s" % lab, "        STA __ax",
                      "        LDA #>%s" % lab, "        STA __ax+1")
        elif kind == "id":
            self.load_var(e[1])
        elif kind == "assign":
            if e[1][0] != "id": sys.exit("p8cc: bad assignment target")
            self.gen_expr(e[2]); self.store_var(e[1][1])
        elif kind == "unary":
            self.gen_expr(e[2])
            if e[1] == "!":
                self.need("__not"); self.emit("        JSR __not")
            else:  # -e  ==  0 - e
                self.need("__sub")
                self.emit("        LDA #0", "        STA __t", "        STA __t+1",
                          "        JSR __sub")
        elif kind == "bin":
            self.gen_bin(e[1], e[2], e[3])
        elif kind == "call":
            self.gen_call(e[1], e[2])
        else:
            sys.exit("p8cc: cannot generate expr %r" % (kind,))

    def gen_bin(self, op, a, b):
        # helper, whether to swap operands, whether to negate the 0/1 result
        plan = {"+": ("__add", False, False), "-": ("__sub", False, False),
                "*": ("__mul", False, False), "==": ("__eq", False, False),
                "!=": ("__eq", False, True), "<": ("__lt", False, False),
                ">": ("__lt", True, False), "<=": ("__lt", True, True),
                ">=": ("__lt", False, True)}[op]
        helper, swap, neg = plan
        lhs, rhs = (b, a) if swap else (a, b)
        self.gen_expr(lhs); self.push_ax()      # left -> stack
        self.gen_expr(rhs)                       # right -> __ax
        self.pop_t()                             # __t = left, __ax = right
        self.need(helper); self.emit("        JSR %s" % helper)
        if neg:
            self.need("__not"); self.emit("        JSR __not")

    def gen_call(self, name, args):
        if name == "putchar":
            self.gen_expr(args[0])
            self.emit("        LDA __ax", "        JSR $0103")
            return
        if name == "puts":
            self.gen_expr(args[0])               # __ax = char*
            self.emit("        LDA __ax", "        TAP1L",
                      "        LDA __ax+1", "        TAP1H",
                      "        JSR $0112",        # BIOS PUTS: (P1)+ until 0
                      "        LDA #10", "        JSR $0103")   # trailing newline
            return
        if args: sys.exit("p8cc: v0.1 user functions take no arguments")
        self.emit("        JSR _f_%s" % name)     # result already in __ax

    # ---- statements ---------------------------------------------------------
    def gen_stmt(self, s):
        k = s[0]
        if k == "block":
            for st in s[1]: self.gen_stmt(st)
        elif k == "decl":
            self.declare(s[2], s[1], "l")
            if s[3] is not None:
                self.gen_expr(s[3]); self.store_var(s[2])
        elif k == "expr":
            self.gen_expr(s[1])
        elif k == "empty":
            pass
        elif k == "return":
            if s[1] is not None: self.gen_expr(s[1])
            self.emit("        JMP _ret_%s" % self.func)
        elif k == "if":
            els = self.lbl("Lelse"); end = self.lbl("Lend")
            self.gen_expr(s[1])
            self.emit("        LDA __ax", "        LDB __ax+1", "        OR",
                      "        JZ %s" % (els if s[3] else end))
            self.gen_stmt(s[2])
            if s[3]:
                self.emit("        JMP %s" % end, "%s:" % els)
                self.gen_stmt(s[3])
            self.emit("%s:" % end)
        elif k == "while":
            top = self.lbl("Ltop"); end = self.lbl("Lend")
            self.emit("%s:" % top)
            self.gen_expr(s[1])
            self.emit("        LDA __ax", "        LDB __ax+1", "        OR",
                      "        JZ %s" % end)
            self.gen_stmt(s[2])
            self.emit("        JMP %s" % top, "%s:" % end)
        else:
            sys.exit("p8cc: cannot generate stmt %r" % (k,))

    # ---- top level ----------------------------------------------------------
    def gen_program(self, decls):
        # globals first so they resolve everywhere
        for d in decls:
            if d[0] == "gvar":
                self.declare(d[2], d[1], "g")
        self.emit("        .org $B000",
                  "        JSR _f_main", "        RTS")
        for d in decls:
            if d[0] == "gvar" and d[3] is not None:
                sys.exit("p8cc: v0.1 global initializers not supported "
                         "(assign inside main instead)")
            if d[0] != "func": continue
            self.func = d[2]; self.locals = {}
            self.emit("_f_%s:" % d[2])
            self.gen_stmt(d[3])
            self.emit("_ret_%s:    RTS" % d[2])
        self.emit_runtime()
        # data section
        self.emit("__ax:   .fill 2", "__t:    .fill 2", "__c:    .fill 1")
        if "__mul" in self.used:
            self.emit("__r:    .fill 2", "__n:    .fill 1")
        self.code.extend(self.data)

    # ---- runtime helpers (only those used) ----------------------------------
    def emit_runtime(self):
        R = {}
        R["__add"] = ["__add:  LDA __t", "        LDB __ax", "        ADD",
                      "        STA __ax", "        LDA #0", "        JNC __add1",
                      "        LDA #1", "__add1: STA __c", "        LDA __t+1",
                      "        LDB __ax+1", "        ADD", "        LDB __c",
                      "        ADD", "        STA __ax+1", "        RTS"]
        R["__sub"] = ["__sub:  LDA __t", "        LDB __ax", "        SUB",
                      "        STA __ax", "        LDA #0", "        JC __sub1",
                      "        LDA #1", "__sub1: STA __c", "        LDA __t+1",
                      "        LDB __ax+1", "        SUB", "        STA __ax+1",
                      "        LDA __c", "        JZ __sub2", "        LDA __ax+1",
                      "        LDB #1", "        SUB", "        STA __ax+1",
                      "__sub2: RTS"]
        R["__mul"] = ["__mul:  LDA #0", "        STA __r", "        STA __r+1",
                      "        LDA #16", "        STA __n",
                      "__mul_l: LDA __ax", "        LDB #1", "        AND",
                      "        JZ __mul_s",
                      "        LDA __r", "        LDB __t", "        ADD",
                      "        STA __r", "        LDA #0", "        JNC __mul_a",
                      "        LDA #1", "__mul_a: STA __c", "        LDA __r+1",
                      "        LDB __t+1", "        ADD", "        LDB __c",
                      "        ADD", "        STA __r+1",
                      "__mul_s: LDA __t", "        SHL", "        STA __t",
                      "        LDA __t+1", "        ROL", "        STA __t+1",
                      "        LDA __ax+1", "        SHR", "        STA __ax+1",
                      "        LDA __ax", "        ROR", "        STA __ax",
                      "        LDA __n", "        DEC", "        STA __n",
                      "        JNZ __mul_l",
                      "        LDA __r", "        STA __ax",
                      "        LDA __r+1", "        STA __ax+1", "        RTS"]
        R["__not"] = ["__not:  LDA __ax", "        LDB __ax+1", "        OR",
                      "        JZ __not1", "        LDA #0", "        JMP __nots",
                      "__not1: LDA #1", "__nots: STA __ax", "        LDA #0",
                      "        STA __ax+1", "        RTS"]
        R["__eq"] = ["__eq:   LDA __t", "        LDB __ax", "        CMP",
                     "        JNZ __eq0", "        LDA __t+1", "        LDB __ax+1",
                     "        CMP", "        JNZ __eq0", "        LDA #1",
                     "        JMP __eqs", "__eq0:  LDA #0", "__eqs:  STA __ax",
                     "        LDA #0", "        STA __ax+1", "        RTS"]
        # unsigned 16-bit  __t < __ax  -> 1/0
        R["__lt"] = ["__lt:   LDA __t+1", "        LDB __ax+1", "        CMP",
                     "        JZ __lt_lo", "        JC __lt0", "        JMP __lt1",
                     "__lt_lo: LDA __t", "        LDB __ax", "        CMP",
                     "        JC __lt0",
                     "__lt1:  LDA #1", "        JMP __lts",
                     "__lt0:  LDA #0", "__lts:  STA __ax", "        LDA #0",
                     "        STA __ax+1", "        RTS"]
        for h in sorted(self.used):
            self.emit(*R[h])


def compile_src(src):
    decls = P(lex(src)).program()
    g = Gen(); g.gen_program(decls)
    return "\n".join(g.code) + "\n"


def main():
    a = sys.argv[1:]
    if not a: sys.exit("usage: p8cc.py prog.c [-o out.asm]")
    src_path = a[0]; out = "a.asm"
    if "-o" in a: out = a[a.index("-o") + 1]
    asm = compile_src(open(src_path).read())
    open(out, "w").write(asm)
    print("p8cc: %s -> %s" % (src_path, out))


if __name__ == "__main__":
    main()
