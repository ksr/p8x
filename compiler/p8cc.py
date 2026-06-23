#!/usr/bin/env python3
"""p8cc - a tiny C cross-compiler for the P8X.

Emits P8X assembly (for assembler/p8xasm.py) targeting the OS transient program
area ($B000), so the output is a RUNnable program. Grown in phases; this one
adds a stack-frame calling convention (parameters, locals, recursion).

Supported now:
  types        int (16-bit), char (8-bit)
  top level    function definitions WITH parameters, global var decls
  statements   { }  decl  if/else  while  return [e];  expr;  ;
  expressions  =  == != < > <= >=  + -  *  unary - !  calls(args)  ( )
               primaries: int/char/string literal, identifier, call
  builtins     putchar(e)   puts(e)        (over the BIOS at $0103 / $0112)

Execution model
  * A 16-bit pseudo-accumulator AX (memory word __ax) holds every expression
    result (the machine has no 16-bit accumulator).
  * The hardware stack (P3) holds expression temporaries (PHA/PLA) and call
    return addresses (JSR/RTS).
  * A separate software C-stack (__csp, grows down from $F800) holds call frames:
    arguments, the saved frame pointer, and locals. __fp points at the saved
    frame pointer of the current frame, so params live at __fp+2, __fp+4, ...
    and locals at __fp-2, __fp-4, .... This makes functions reentrant, so
    recursion works. Globals keep static storage.
  Binary operators are compact runtime-helper calls, emitted only when used.

Usage:  p8cc.py prog.c [-o prog.asm]
Then:   p8xasm.py prog.asm -o prog.bin --base 0xB000
"""
import sys

CSTACK_TOP = 0xF800            # software C-stack grows down from here

# --------------------------------------------------------------------------- #
# Lexer
# --------------------------------------------------------------------------- #
KEYWORDS = {"int", "char", "void", "if", "else", "while", "return"}
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
        if self.t[self.i][1] != v: self.err("expected %r, got %r" % (v, self.t[self.i][1]))
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
        if self.val() in ("int", "char", "void"): return self.next()[1]
        self.err("expected a type")

    def toplevel(self):
        ty = self.typespec()
        name = self.next()
        if name[0] != "id": self.err("expected name")
        name = name[1]
        if self.accept("("):
            params = []
            if self.val() != ")":
                params.append(self.param())
                while self.accept(","): params.append(self.param())
            self.eat(")")
            body = self.block()
            return ("func", ty, name, params, body)
        init = None
        if self.accept("="): init = self.expr()
        self.eat(";")
        return ("gvar", ty, name, init)

    def param(self):
        pty = self.typespec()
        nm = self.next()
        if nm[0] != "id": self.err("expected parameter name")
        return (pty, nm[1])

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
            self.eat(";"); return ("decl", ty, name, init)
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

    def expr(self): return self.assign()

    def assign(self):
        left = self.binary(0)
        if self.val() == "=":
            self.next(); return ("assign", left, self.assign())
        return left

    LEVELS = [["==", "!="], ["<", ">", "<=", ">="], ["+", "-"], ["*"]]

    def binary(self, lvl):
        if lvl >= len(self.LEVELS): return self.unary()
        left = self.binary(lvl + 1)
        while self.val() in self.LEVELS[lvl]:
            op = self.next()[1]
            left = ("bin", op, left, self.binary(lvl + 1))
        return left

    def unary(self):
        if self.val() in ("-", "!"):
            op = self.next()[1]; return ("unary", op, self.unary())
        return self.postfix()

    def postfix(self):
        e = self.primary()
        while self.val() == "(":
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
        self.locals = {}      # name -> (frame offset:int, type)  (per function)
        self.strings = {}     # tuple(bytes) -> label
        self.used = set()
        self.nl = 0
        self.func = None

    def lbl(self, base="L"): self.nl += 1; return "%s%d" % (base, self.nl)
    def emit(self, *lines): self.code.extend(lines)
    def need(self, h): self.used.add(h)

    # ---- variables ----------------------------------------------------------
    def declare_global(self, name, ty):
        lab = "_g_" + name
        self.globals[name] = (lab, ty)
        self.data.append("%s:    .fill %d" % (lab, 2 if ty == "int" else 1))

    def string(self, bs):
        key = tuple(bs)
        if key not in self.strings:
            lab = self.lbl("__s"); self.strings[key] = lab
            body = ",".join(str(b) for b in bs)
            self.data.append("%s:    .byte %s,0" % (lab, body) if bs
                             else "%s:    .byte 0" % lab)
        return self.strings[key]

    def lea(self, off):                       # P1 = __fp + off  (off signed)
        o = off & 0xFFFF
        self.need("__lea")
        self.emit("        LDA #%d" % (o & 0xFF), "        STA __off",
                  "        LDA #%d" % (o >> 8), "        STA __off+1",
                  "        JSR __lea")

    def set_ax_const(self, v):
        v &= 0xFFFF
        self.emit("        LDA #%d" % (v & 0xFF), "        STA __ax",
                  "        LDA #%d" % (v >> 8), "        STA __ax+1")

    def load_var(self, name):
        if name in self.locals:
            off, ty = self.locals[name]
            self.lea(off)
            if ty == "int":
                self.emit("        LDA (P1)+", "        STA __ax",
                          "        LDA (P1)", "        STA __ax+1")
            else:
                self.emit("        LDA (P1)", "        STA __ax",
                          "        LDA #0", "        STA __ax+1")
        elif name in self.globals:
            lab, ty = self.globals[name]
            self.emit("        LDA %s" % lab, "        STA __ax")
            self.emit(*(["        LDA %s+1" % lab, "        STA __ax+1"] if ty == "int"
                        else ["        LDA #0", "        STA __ax+1"]))
        else:
            sys.exit("p8cc: undeclared identifier %r" % name)

    def store_var(self, name):                # __ax -> var
        if name in self.locals:
            off, ty = self.locals[name]
            self.lea(off)                     # __lea preserves __ax
            if ty == "int":
                self.emit("        LDA __ax", "        STA (P1)+",
                          "        LDA __ax+1", "        STA (P1)")
            else:
                self.emit("        LDA __ax", "        STA (P1)")
        elif name in self.globals:
            lab, ty = self.globals[name]
            self.emit("        LDA __ax", "        STA %s" % lab)
            if ty == "int":
                self.emit("        LDA __ax+1", "        STA %s+1" % lab)
        else:
            sys.exit("p8cc: undeclared identifier %r" % name)

    # ---- expressions (result in __ax) --------------------------------------
    def push_ax(self): self.emit("        LDA __ax", "        PHA",
                                  "        LDA __ax+1", "        PHA")
    def pop_t(self): self.emit("        PLA", "        STA __t+1",
                               "        PLA", "        STA __t")

    def gen_expr(self, e):
        k = e[0]
        if k == "num": self.set_ax_const(e[1])
        elif k == "str":
            lab = self.string(e[1])
            self.emit("        LDA #<%s" % lab, "        STA __ax",
                      "        LDA #>%s" % lab, "        STA __ax+1")
        elif k == "id": self.load_var(e[1])
        elif k == "assign":
            if e[1][0] != "id": sys.exit("p8cc: bad assignment target")
            self.gen_expr(e[2]); self.store_var(e[1][1])
        elif k == "unary":
            self.gen_expr(e[2])
            if e[1] == "!":
                self.need("__not"); self.emit("        JSR __not")
            else:
                self.need("__sub")
                self.emit("        LDA #0", "        STA __t", "        STA __t+1",
                          "        JSR __sub")
        elif k == "bin": self.gen_bin(e[1], e[2], e[3])
        elif k == "call": self.gen_call(e[1], e[2])
        else: sys.exit("p8cc: cannot generate expr %r" % (k,))

    def gen_bin(self, op, a, b):
        plan = {"+": ("__add", False, False), "-": ("__sub", False, False),
                "*": ("__mul", False, False), "==": ("__eq", False, False),
                "!=": ("__eq", False, True), "<": ("__lt", False, False),
                ">": ("__lt", True, False), "<=": ("__lt", True, True),
                ">=": ("__lt", False, True)}[op]
        helper, swap, neg = plan
        lhs, rhs = (b, a) if swap else (a, b)
        self.gen_expr(lhs); self.push_ax()
        self.gen_expr(rhs); self.pop_t()        # __t = left, __ax = right
        self.need(helper); self.emit("        JSR %s" % helper)
        if neg:
            self.need("__not"); self.emit("        JSR __not")

    def gen_call(self, name, args):
        if name == "putchar":
            self.gen_expr(args[0])
            self.emit("        LDA __ax", "        JSR $0103"); return
        if name == "puts":
            self.gen_expr(args[0])
            self.emit("        LDA __ax", "        TAP1L", "        LDA __ax+1",
                      "        TAP1H", "        JSR $0112",
                      "        LDA #10", "        JSR $0103"); return
        # user function: push args right-to-left, call, caller cleans up.
        for a in reversed(args):
            self.gen_expr(a)
            self.need("__push"); self.emit("        JSR __push")
        self.emit("        JSR _f_%s" % name)
        if args:
            n = 2 * len(args)
            skip = self.lbl("Lcl")
            self.emit("        LDA __csp", "        LDB #%d" % n, "        ADD",
                      "        STA __csp", "        JNC %s" % skip,
                      "        LDA __csp+1", "        INC", "        STA __csp+1",
                      "%s:" % skip)

    # ---- statements ---------------------------------------------------------
    def gen_stmt(self, s):
        k = s[0]
        if k == "block":
            for st in s[1]: self.gen_stmt(st)
        elif k == "decl":
            if s[3] is not None:
                self.gen_expr(s[3]); self.store_var(s[2])
        elif k == "expr": self.gen_expr(s[1])
        elif k == "empty": pass
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
        else: sys.exit("p8cc: cannot generate stmt %r" % (k,))

    # ---- functions ----------------------------------------------------------
    def collect_decls(self, s):
        k = s[0]
        if k == "decl": yield s
        elif k == "block":
            for st in s[1]: yield from self.collect_decls(st)
        elif k == "if":
            yield from self.collect_decls(s[2])
            if s[3]: yield from self.collect_decls(s[3])
        elif k == "while":
            yield from self.collect_decls(s[2])

    def compile_func(self, ty, name, params, body):
        self.func = name
        self.locals = {}
        for i, (pty, pnm) in enumerate(params):     # params: __fp+2, +4, ...
            self.locals[pnm] = (2 + 2 * i, pty)
        loff = -2                                   # locals: __fp-2, -4, ...
        for d in self.collect_decls(body):
            if d[2] not in self.locals:
                self.locals[d[2]] = (loff, d[1]); loff -= 2
        localsize = -loff - 2
        self.emit("_f_%s:" % name)
        self.need("__enter"); self.emit("        JSR __enter")
        if localsize:
            skip = self.lbl("Lfr")
            self.emit("        LDA __csp", "        LDB #%d" % localsize,
                      "        SUB", "        STA __csp", "        JC %s" % skip,
                      "        LDA __csp+1", "        LDB #1", "        SUB",
                      "        STA __csp+1", "%s:" % skip)
        self.gen_stmt(body)
        self.emit("_ret_%s:" % name)
        self.need("__leave"); self.emit("        JSR __leave", "        RTS")

    # ---- top level ----------------------------------------------------------
    def gen_program(self, decls):
        for d in decls:
            if d[0] == "gvar":
                if d[3] is not None:
                    sys.exit("p8cc: global initializers not supported "
                             "(assign inside a function instead)")
                self.declare_global(d[2], d[1])
        self.emit("        .org $B000",
                  "        LDA #%d" % (CSTACK_TOP & 0xFF), "        STA __csp",
                  "        LDA #%d" % (CSTACK_TOP >> 8), "        STA __csp+1",
                  "        JSR _f_main", "        RTS")
        for d in decls:
            if d[0] == "func":
                self.compile_func(d[1], d[2], d[3], d[4])
        self.emit_runtime()
        self.emit("__ax:   .fill 2", "__t:    .fill 2", "__c:    .fill 1",
                  "__fp:   .fill 2", "__csp:  .fill 2", "__off:  .fill 2")
        if "__mul" in self.used:
            self.emit("__r:    .fill 2", "__n:    .fill 1")
        self.code.extend(self.data)

    # ---- runtime helpers ----------------------------------------------------
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
        R["__lt"] = ["__lt:   LDA __t+1", "        LDB __ax+1", "        CMP",
                     "        JZ __lt_lo", "        JC __lt0", "        JMP __lt1",
                     "__lt_lo: LDA __t", "        LDB __ax", "        CMP",
                     "        JC __lt0",
                     "__lt1:  LDA #1", "        JMP __lts",
                     "__lt0:  LDA #0", "__lts:  STA __ax", "        LDA #0",
                     "        STA __ax+1", "        RTS"]
        # --- frame / C-stack helpers ---
        # __push: push __ax onto the C-stack (csp -= 2; [csp] = __ax)
        R["__push"] = ["__push: LDA __csp", "        LDB #2", "        SUB",
                       "        STA __csp", "        JC __pu1", "        LDA __csp+1",
                       "        LDB #1", "        SUB", "        STA __csp+1",
                       "__pu1:  LDA __csp", "        TAP1L", "        LDA __csp+1",
                       "        TAP1H", "        LDA __ax", "        STA (P1)+",
                       "        LDA __ax+1", "        STA (P1)", "        RTS"]
        # __enter: push the caller's FP, then FP = csp (start of this frame)
        R["__enter"] = ["__enter: LDA __csp", "        LDB #2", "        SUB",
                        "        STA __csp", "        JC __en1", "        LDA __csp+1",
                        "        LDB #1", "        SUB", "        STA __csp+1",
                        "__en1:  LDA __csp", "        TAP1L", "        LDA __csp+1",
                        "        TAP1H", "        LDA __fp", "        STA (P1)+",
                        "        LDA __fp+1", "        STA (P1)",
                        "        LDA __csp", "        STA __fp",
                        "        LDA __csp+1", "        STA __fp+1", "        RTS"]
        # __leave: csp = fp (drop locals); pop the saved FP; csp += 2
        R["__leave"] = ["__leave: LDA __fp", "        STA __csp", "        LDA __fp+1",
                        "        STA __csp+1", "        LDA __csp", "        TAP1L",
                        "        LDA __csp+1", "        TAP1H", "        LDA (P1)+",
                        "        STA __fp", "        LDA (P1)", "        STA __fp+1",
                        "        LDA __csp", "        LDB #2", "        ADD",
                        "        STA __csp", "        JNC __lv1", "        LDA __csp+1",
                        "        INC", "        STA __csp+1", "__lv1:  RTS"]
        # __lea: P1 = __fp + __off (signed)
        R["__lea"] = ["__lea:  LDA __fp", "        LDB __off", "        ADD",
                      "        STA __t", "        LDA #0", "        JNC __la1",
                      "        LDA #1", "__la1:  STA __c", "        LDA __fp+1",
                      "        LDB __off+1", "        ADD", "        LDB __c",
                      "        ADD", "        STA __t+1", "        LDA __t",
                      "        TAP1L", "        LDA __t+1", "        TAP1H",
                      "        RTS"]
        for h in sorted(self.used):
            self.emit(*R[h])


def compile_src(src):
    g = Gen(); g.gen_program(P(lex(src)).program())
    return "\n".join(g.code) + "\n"


def main():
    a = sys.argv[1:]
    if not a: sys.exit("usage: p8cc.py prog.c [-o out.asm]")
    src_path = a[0]; out = "a.asm"
    if "-o" in a: out = a[a.index("-o") + 1]
    open(out, "w").write(compile_src(open(src_path).read()))
    print("p8cc: %s -> %s" % (src_path, out))


if __name__ == "__main__":
    main()
