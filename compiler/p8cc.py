#!/usr/bin/env python3
"""p8cc - a tiny C cross-compiler for the P8X.

Emits P8X assembly (for assembler/p8xasm.py) targeting the OS transient program
area ($B000), so the output is a RUNnable program. Grown in phases.

Supported now:
  types        int (16-bit), char (8-bit), pointers (T *), arrays (T a[N])
  top level    function definitions with parameters, global var decls
  statements   { }  decl  if/else  while  for(e;e;e)  return [e];  expr;  ;
  expressions  =  || &&  | ^ &  == !=  < > <= >=  << >>  + - * / %
               unary - ! ~ & *   a[i]   calls(args)
               primaries: int/char/string literal, identifier, call
  builtins     getchar()  putchar(e)  puts(e)   (BIOS $0100 / $0103 / $0112)
  note         for-init is an expression, not a declaration (locals are
               function-scoped; declare the loop var before the loop)

Execution model
  * 16-bit pseudo-accumulator AX (memory word __ax) holds every expression
    result (the machine has no 16-bit accumulator).
  * Hardware stack (P3) holds expression temporaries (PHA/PLA) + return addrs.
  * Software C-stack (__csp, grows down from $F800) holds call frames: args, the
    saved frame pointer, and locals. __fp points at the saved FP, so params are
    at __fp+2,+4,... and locals at __fp-2,-4,... -> reentrant -> recursion works.
    Globals keep static storage.
  Types are tracked so pointer arithmetic scales by element size and a
  dereference loads/stores the right width (int/pointer = 2 bytes, char = 1).

Usage:  p8cc.py prog.c [-o prog.asm]   then  p8xasm.py prog.asm -o prog.bin --base 0xB000
"""
import sys

CSTACK_TOP = 0xF800

# --------------------------------------------------------------------------- #
# Lexer
# --------------------------------------------------------------------------- #
KEYWORDS = {"int", "char", "void", "if", "else", "while", "for", "return"}
PUNCT = ["==", "!=", "<=", ">=", "<<", ">>", "&&", "||",
         "{", "}", "(", ")", "[", "]", ";", ",", "=",
         "+", "-", "*", "/", "%", "<", ">", "!", "&", "|", "^", "~"]


def lex(src):
    toks, i, n, line = [], 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n": line += 1; i += 1; continue
        if c in " \t\r": i += 1; continue
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
# Parser -> AST.  A declared type is (base, ptr, count): base in {int,char},
# ptr = pointer depth, count = array length (0 = scalar/pointer).
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
        d = []
        while self.kind() != "eof": d.append(self.toplevel())
        return d

    def base_and_ptr(self):
        if self.val() not in ("int", "char", "void"): self.err("expected a type")
        base = self.next()[1]; ptr = 0
        while self.accept("*"): ptr += 1
        return base, ptr

    def toplevel(self):
        base, ptr = self.base_and_ptr()
        name = self.next()
        if name[0] != "id": self.err("expected name")
        name = name[1]
        if self.accept("("):
            params = []
            if self.val() != ")":
                params.append(self.param())
                while self.accept(","): params.append(self.param())
            self.eat(")")
            return ("func", (base, ptr, 0), name, params, self.block())
        count = 0
        if self.accept("["):
            count = self.next()[1]; self.eat("]")
        init = None
        if self.accept("="): init = self.expr()
        self.eat(";")
        return ("gvar", (base, ptr, count), name, init)

    def param(self):
        base, ptr = self.base_and_ptr()
        nm = self.next()
        if nm[0] != "id": self.err("expected parameter name")
        return ((base, ptr, 0), nm[1])

    def block(self):
        self.eat("{"); s = []
        while self.val() != "}": s.append(self.stmt())
        self.eat("}"); return ("block", s)

    def stmt(self):
        v = self.val()
        if v == "{": return self.block()
        if v in ("int", "char"):
            base, ptr = self.base_and_ptr()
            name = self.next()[1]; count = 0
            if self.accept("["):
                count = self.next()[1]; self.eat("]")
            init = None
            if self.accept("="): init = self.expr()
            self.eat(";"); return ("decl", (base, ptr, count), name, init)
        if v == "if":
            self.next(); self.eat("("); c = self.expr(); self.eat(")")
            then = self.stmt(); els = self.stmt() if self.accept("else") else None
            return ("if", c, then, els)
        if v == "while":
            self.next(); self.eat("("); c = self.expr(); self.eat(")")
            return ("while", c, self.stmt())
        if v == "for":
            self.next(); self.eat("(")
            init = None if self.val() == ";" else self.expr(); self.eat(";")
            cond = None if self.val() == ";" else self.expr(); self.eat(";")
            post = None if self.val() == ")" else self.expr(); self.eat(")")
            return ("for", init, cond, post, self.stmt())
        if v == "return":
            self.next(); e = None if self.val() == ";" else self.expr()
            self.eat(";"); return ("return", e)
        if v == ";": self.next(); return ("empty",)
        e = self.expr(); self.eat(";"); return ("expr", e)

    def expr(self): return self.assign()

    def assign(self):
        left = self.logic_or()
        if self.val() == "=":
            self.next(); return ("assign", left, self.assign())
        return left

    def logic_or(self):
        left = self.logic_and()
        while self.val() == "||":
            self.next(); left = ("logor", left, self.logic_and())
        return left

    def logic_and(self):
        left = self.binary(0)
        while self.val() == "&&":
            self.next(); left = ("logand", left, self.binary(0))
        return left

    LEVELS = [["|"], ["^"], ["&"], ["==", "!="], ["<", ">", "<=", ">="],
              ["<<", ">>"], ["+", "-"], ["*", "/", "%"]]

    def binary(self, lvl):
        if lvl >= len(self.LEVELS): return self.unary()
        left = self.binary(lvl + 1)
        while self.val() in self.LEVELS[lvl]:
            op = self.next()[1]
            left = ("bin", op, left, self.binary(lvl + 1))
        return left

    def unary(self):
        v = self.val()
        if v in ("-", "!", "&", "*", "~"):
            self.next(); return ("unary", v, self.unary())
        return self.postfix()

    def postfix(self):
        e = self.primary()
        while True:
            if self.val() == "(":
                self.next(); args = []
                if self.val() != ")":
                    args.append(self.expr())
                    while self.accept(","): args.append(self.expr())
                self.eat(")")
                if e[0] != "id": self.err("call of non-function")
                e = ("call", e[1], args)
            elif self.val() == "[":
                self.next(); idx = self.expr(); self.eat("]")
                e = ("index", e, idx)
            else:
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
def sizeof(base, ptr):
    return 2 if (ptr > 0 or base == "int") else 1


class Gen:
    def __init__(self):
        self.code = []; self.data = []
        self.globals = {}     # name -> (label, base, ptr, count)
        self.locals = {}      # name -> (offset, base, ptr, count)
        self.funcs = {}       # name -> (base, ptr) return type
        self.strings = {}
        self.used = set()
        self.nl = 0
        self.func = None

    def lbl(self, b="L"): self.nl += 1; return "%s%d" % (b, self.nl)
    def emit(self, *l): self.code.extend(l)
    def need(self, h): self.used.add(h)

    # ---- types --------------------------------------------------------------
    def vinfo(self, name):
        if name in self.locals:
            off, base, ptr, count = self.locals[name]; return ("l", off, base, ptr, count)
        if name in self.globals:
            lab, base, ptr, count = self.globals[name]; return ("g", lab, base, ptr, count)
        sys.exit("p8cc: undeclared identifier %r" % name)

    def typeof(self, e):                      # -> (base, ptr) of e's value (arrays decay)
        k = e[0]
        if k == "num": return ("int", 0)
        if k == "str": return ("char", 1)
        if k == "id":
            _, _, base, ptr, count = self.vinfo(e[1])
            return (base, ptr + 1) if count else (base, ptr)
        if k == "unary":
            if e[1] == "&":
                b, p = self.typeof_lval(e[2]); return (b, p + 1)
            if e[1] == "*":
                b, p = self.typeof(e[2]); return (b, p - 1)
            return ("int", 0)
        if k == "index":
            b, p = self.typeof(e[1]); return (b, p - 1)
        if k == "assign": return self.typeof_lval(e[1])
        if k == "call":
            if e[1] == "getchar": return ("int", 0)
            return self.funcs.get(e[1], ("int", 0))   # declared return type
        if k == "bin":
            if e[1] in ("+", "-"):
                lt = self.typeof(e[2]); rt = self.typeof(e[3])
                if lt[1] > 0: return lt
                if rt[1] > 0: return rt
            return ("int", 0)
        return ("int", 0)

    def typeof_lval(self, e):                 # type as an lvalue (no array decay)
        if e[0] == "id":
            _, _, base, ptr, count = self.vinfo(e[1]); return (base, ptr)
        if e[0] == "unary" and e[1] == "*":
            b, p = self.typeof(e[2]); return (b, p - 1)
        if e[0] == "index":
            b, p = self.typeof(e[1]); return (b, p - 1)
        sys.exit("p8cc: not an lvalue")

    # ---- helpers ------------------------------------------------------------
    def lea(self, off):                       # P1 = __fp + off
        o = off & 0xFFFF
        self.need("__lea")
        self.emit("        LDA #%d" % (o & 0xFF), "        STA __off",
                  "        LDA #%d" % (o >> 8), "        STA __off+1",
                  "        JSR __lea")

    def set_ax_const(self, v):
        v &= 0xFFFF
        self.emit("        LDA #%d" % (v & 0xFF), "        STA __ax",
                  "        LDA #%d" % (v >> 8), "        STA __ax+1")

    def push_ax(self): self.emit("        LDA __ax", "        PHA",
                                 "        LDA __ax+1", "        PHA")
    def pop_t(self): self.emit("        PLA", "        STA __t+1",
                              "        PLA", "        STA __t")

    def ax_to_p1(self): self.emit("        LDA __ax", "        TAP1L",
                                  "        LDA __ax+1", "        TAP1H")

    # ---- addresses (lvalues): result address in __ax -----------------------
    def gen_address(self, e):
        k = e[0]
        if k == "id":
            kind = self.vinfo(e[1])
            if kind[0] == "l":
                self.lea(kind[1])                       # P1 = __fp+off
                self.emit("        TPA1L", "        STA __ax",
                          "        TPA1H", "        STA __ax+1")
            else:
                lab = kind[1]
                self.emit("        LDA #<%s" % lab, "        STA __ax",
                          "        LDA #>%s" % lab, "        STA __ax+1")
        elif k == "unary" and e[1] == "*":
            self.gen_expr(e[2])                          # AX = pointer value = address
        elif k == "index":
            self.gen_expr(e[1]); self.push_ax()          # base address
            self.gen_expr(e[2])                          # index
            esz = sizeof(*self.typeof(e[1]))             # element size (sizeof of decayed-pointer? )
            # typeof(e[1]) is a pointer (b,p); element size = sizeof(b, p-1)
            b, p = self.typeof(e[1]); esz = sizeof(b, p - 1)
            if esz == 2:
                self.emit("        LDA __ax", "        SHL", "        STA __ax",
                          "        LDA __ax+1", "        ROL", "        STA __ax+1")
            self.pop_t()                                 # __t = base
            self.need("__add"); self.emit("        JSR __add")
        else:
            sys.exit("p8cc: not an lvalue")

    def load_deref(self, base, ptr):          # AX = *(AX) of type (base,ptr)
        self.ax_to_p1()
        if sizeof(base, ptr) == 2:
            self.emit("        LDA (P1)+", "        STA __ax",
                      "        LDA (P1)", "        STA __ax+1")
        else:
            self.emit("        LDA (P1)", "        STA __ax",
                      "        LDA #0", "        STA __ax+1")

    # ---- expressions (result in __ax) --------------------------------------
    def gen_expr(self, e):
        k = e[0]
        if k == "num": self.set_ax_const(e[1])
        elif k == "str":
            lab = self.string(e[1])
            self.emit("        LDA #<%s" % lab, "        STA __ax",
                      "        LDA #>%s" % lab, "        STA __ax+1")
        elif k == "id":
            kind = self.vinfo(e[1])
            base, ptr, count = kind[2], kind[3], kind[4]
            if count:                                    # array decays to its address
                self.gen_address(e)
            elif kind[0] == "l":
                self.lea(kind[1])
                if sizeof(base, ptr) == 2:
                    self.emit("        LDA (P1)+", "        STA __ax",
                              "        LDA (P1)", "        STA __ax+1")
                else:
                    self.emit("        LDA (P1)", "        STA __ax",
                              "        LDA #0", "        STA __ax+1")
            else:
                lab = kind[1]
                self.emit("        LDA %s" % lab, "        STA __ax")
                self.emit(*(["        LDA %s+1" % lab, "        STA __ax+1"]
                            if sizeof(base, ptr) == 2 else
                            ["        LDA #0", "        STA __ax+1"]))
        elif k == "unary":
            if e[1] == "&": self.gen_address(e[2])
            elif e[1] == "*":
                self.gen_expr(e[2]); self.load_deref(*self.typeof_lval(e))
            elif e[1] == "!":
                self.gen_expr(e[2]); self.need("__not"); self.emit("        JSR __not")
            elif e[1] == "~":                                # bitwise NOT: 255-byte each
                self.gen_expr(e[2])
                self.emit("        LDA #255", "        LDB __ax", "        SUB",
                          "        STA __ax", "        LDA #255", "        LDB __ax+1",
                          "        SUB", "        STA __ax+1")
            else:  # -e
                self.gen_expr(e[2]); self.need("__sub")
                self.emit("        LDA #0", "        STA __t", "        STA __t+1",
                          "        JSR __sub")
        elif k == "index":
            self.gen_address(e); self.load_deref(*self.typeof_lval(e))
        elif k == "assign": self.gen_assign(e[1], e[2])
        elif k == "logand": self.gen_logand(e[1], e[2])
        elif k == "logor": self.gen_logor(e[1], e[2])
        elif k == "bin": self.gen_bin(e[1], e[2], e[3])
        elif k == "call": self.gen_call(e[1], e[2])
        else: sys.exit("p8cc: cannot generate expr %r" % (k,))

    def gen_assign(self, lhs, rhs):
        self.gen_expr(rhs); self.push_ax()               # value on P3
        self.gen_address(lhs)                            # AX = dest address
        self.ax_to_p1()                                  # P1 = dest
        self.pop_t()                                     # __t = value
        if sizeof(*self.typeof_lval(lhs)) == 2:
            self.emit("        LDA __t", "        STA (P1)+",
                      "        LDA __t+1", "        STA (P1)")
        else:
            self.emit("        LDA __t", "        STA (P1)")
        self.emit("        LDA __t", "        STA __ax",   # assignment yields the value
                  "        LDA __t+1", "        STA __ax+1")

    def gen_bin(self, op, a, b):
        plan = {"+": ("__add", False, False), "-": ("__sub", False, False),
                "*": ("__mul", False, False), "/": ("__div", False, False),
                "%": ("__mod", False, False), "==": ("__eq", False, False),
                "!=": ("__eq", False, True), "<": ("__lt", False, False),
                ">": ("__lt", True, False), "<=": ("__lt", True, True),
                ">=": ("__lt", False, True),
                "&": ("__and", False, False), "|": ("__or", False, False),
                "^": ("__xor", False, False), "<<": ("__shl", False, False),
                ">>": ("__shr", False, False)}[op]
        helper, swap, neg = plan
        # pointer arithmetic: scale the integer operand by element size.
        scale = 0
        if op in ("+", "-"):
            lt, rt = self.typeof(a), self.typeof(b)
            if lt[1] > 0 and rt[1] == 0:
                scale = sizeof(lt[0], lt[1] - 1)          # left is pointer, scale right
            elif op == "+" and rt[1] > 0 and lt[1] == 0:
                a, b = b, a                               # commute so pointer is left
                scale = sizeof(rt[0], rt[1] - 1)
        lhs, rhs = (b, a) if swap else (a, b)
        self.gen_expr(lhs); self.push_ax()
        self.gen_expr(rhs)
        if scale == 2:                                    # scale the right (int) operand
            self.emit("        LDA __ax", "        SHL", "        STA __ax",
                      "        LDA __ax+1", "        ROL", "        STA __ax+1")
        self.pop_t()
        self.need(helper); self.emit("        JSR %s" % helper)
        if neg:
            self.need("__not"); self.emit("        JSR __not")

    def gen_logand(self, a, b):                          # short-circuit && -> 0/1
        false = self.lbl("Land0"); end = self.lbl("Lande")
        self.gen_expr(a)
        self.emit("        LDA __ax", "        LDB __ax+1", "        OR",
                  "        JZ %s" % false)
        self.gen_expr(b)
        self.emit("        LDA __ax", "        LDB __ax+1", "        OR",
                  "        JZ %s" % false,
                  "        LDA #1", "        STA __ax", "        LDA #0",
                  "        STA __ax+1", "        JMP %s" % end,
                  "%s:    LDA #0" % false, "        STA __ax", "        STA __ax+1",
                  "%s:" % end)

    def gen_logor(self, a, b):                           # short-circuit || -> 0/1
        true = self.lbl("Lor1"); end = self.lbl("Lore")
        self.gen_expr(a)
        self.emit("        LDA __ax", "        LDB __ax+1", "        OR",
                  "        JNZ %s" % true)
        self.gen_expr(b)
        self.emit("        LDA __ax", "        LDB __ax+1", "        OR",
                  "        JNZ %s" % true,
                  "        LDA #0", "        STA __ax", "        STA __ax+1",
                  "        JMP %s" % end,
                  "%s:    LDA #1" % true, "        STA __ax", "        LDA #0",
                  "        STA __ax+1", "%s:" % end)

    def gen_call(self, name, args):
        if name == "getchar":                            # BIOS CONIN -> char
            self.emit("        JSR $0100", "        STA __ax",
                      "        LDA #0", "        STA __ax+1"); return
        if name == "putchar":
            self.gen_expr(args[0])
            self.emit("        LDA __ax", "        JSR $0103"); return
        if name == "puts":
            self.gen_expr(args[0])
            self.emit("        LDA __ax", "        TAP1L", "        LDA __ax+1",
                      "        TAP1H", "        JSR $0112",
                      "        LDA #10", "        JSR $0103"); return
        for a in reversed(args):
            self.gen_expr(a); self.need("__push"); self.emit("        JSR __push")
        self.emit("        JSR _f_%s" % name)
        if args:
            n = 2 * len(args); skip = self.lbl("Lcl")
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
                self.gen_assign(("id", s[2]), s[3])
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
        elif k == "for":                                  # for(init; cond; post) body
            init, cond, post, body = s[1], s[2], s[3], s[4]
            top = self.lbl("Ltop"); end = self.lbl("Lend")
            if init is not None: self.gen_expr(init)
            self.emit("%s:" % top)
            if cond is not None:
                self.gen_expr(cond)
                self.emit("        LDA __ax", "        LDB __ax+1", "        OR",
                          "        JZ %s" % end)
            self.gen_stmt(body)
            if post is not None: self.gen_expr(post)
            self.emit("        JMP %s" % top, "%s:" % end)
        else: sys.exit("p8cc: cannot generate stmt %r" % (k,))

    # ---- functions / top level ---------------------------------------------
    def string(self, bs):
        key = tuple(bs)
        if key not in self.strings:
            lab = self.lbl("__s"); self.strings[key] = lab
            body = ",".join(str(b) for b in bs)
            self.data.append("%s:    .byte %s,0" % (lab, body) if bs
                             else "%s:    .byte 0" % lab)
        return self.strings[key]

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
        elif k == "for":
            yield from self.collect_decls(s[4])

    def compile_func(self, name, params, body):
        self.func = name; self.locals = {}
        for i, ((base, ptr, _), pnm) in enumerate(params):
            self.locals[pnm] = (2 + 2 * i, base, ptr, 0)   # params: 2-byte slots
        loff = 0
        for d in self.collect_decls(body):
            (base, ptr, count), nm = d[1], d[2]
            if nm in self.locals: continue
            size = (count * sizeof(base, ptr)) if count else 2
            loff -= size
            self.locals[nm] = (loff, base, ptr, count)
        localsize = -loff
        self.emit("_f_%s:" % name)
        self.need("__enter"); self.emit("        JSR __enter")
        if localsize:
            skip = self.lbl("Lfr")
            self.emit("        LDA __csp", "        LDB #%d" % localsize, "        SUB",
                      "        STA __csp", "        JC %s" % skip, "        LDA __csp+1",
                      "        LDB #1", "        SUB", "        STA __csp+1", "%s:" % skip)
        self.gen_stmt(body)
        self.emit("_ret_%s:" % name)
        self.need("__leave"); self.emit("        JSR __leave", "        RTS")

    def declare_global(self, base, ptr, count, name):
        lab = "_g_" + name
        self.globals[name] = (lab, base, ptr, count)
        self.data.append("%s:    .fill %d" % (lab, (count * sizeof(base, ptr)) if count
                                              else sizeof(base, ptr)))

    def gen_program(self, decls):
        for d in decls:
            if d[0] == "func":
                self.funcs[d[2]] = (d[1][0], d[1][1])   # name -> return (base, ptr)
        for d in decls:
            if d[0] == "gvar":
                if d[3] is not None:
                    sys.exit("p8cc: global initializers not supported")
                self.declare_global(d[1][0], d[1][1], d[1][2], d[2])
        self.emit("        .org $B000",
                  "        LDA #%d" % (CSTACK_TOP & 0xFF), "        STA __csp",
                  "        LDA #%d" % (CSTACK_TOP >> 8), "        STA __csp+1",
                  "        JSR _f_main", "        RTS")
        for d in decls:
            if d[0] == "func": self.compile_func(d[2], d[3], d[4])
        self.emit_runtime()
        self.emit("__ax:   .fill 2", "__t:    .fill 2", "__c:    .fill 1",
                  "__fp:   .fill 2", "__csp:  .fill 2", "__off:  .fill 2")
        if "__mul" in self.used:
            self.emit("__r:    .fill 2")
        if {"__mul", "__div", "__mod", "__shl", "__shr"} & self.used:
            self.emit("__n:    .fill 1")
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
        # __divmod: __t / __ax -> quotient __r, remainder __ax (unsigned 16-bit,
        # restoring long division). __div and __mod both call it.
        # __t / __ax: quotient -> __t (in place), remainder -> __dr. Restoring
        # long division: shift the 32-bit [__dr:__t] left (low byte first!) so the
        # dividend's top bit enters the remainder, then conditionally subtract.
        R["__divmod"] = ["__divmod: LDA #0", "        STA __dr", "        STA __dr+1",
                         "        LDA #16", "        STA __n",
                         "__dm_l: LDA __t", "        SHL", "        STA __t",   # [__dr:__t] <<= 1
                         "        LDA __t+1", "        ROL", "        STA __t+1",
                         "        LDA __dr", "        ROL", "        STA __dr",
                         "        LDA __dr+1", "        ROL", "        STA __dr+1",
                         # if remainder >= divisor: subtract it, set quotient bit 0
                         "        LDA __dr+1", "        LDB __ax+1", "        CMP",
                         "        JZ __dm_lo", "        JC __dm_ge", "        JMP __dm_no",
                         "__dm_lo: LDA __dr", "        LDB __ax", "        CMP",
                         "        JNC __dm_no",
                         "__dm_ge: LDA __dr", "        LDB __ax", "        SUB",
                         "        STA __dr", "        LDA #0", "        JC __dm_b",
                         "        LDA #1", "__dm_b: STA __c", "        LDA __dr+1",
                         "        LDB __ax+1", "        SUB", "        LDB __c",
                         "        SUB", "        STA __dr+1",
                         "        LDA __t", "        LDB #1", "        OR",
                         "        STA __t",            # set low quotient bit
                         "__dm_no: LDA __n", "        DEC", "        STA __n",
                         "        JNZ __dm_l",
                         "        RTS"]
        R["__div"] = ["__div:  JSR __divmod", "        LDA __t", "        STA __ax",
                      "        LDA __t+1", "        STA __ax+1", "        RTS"]
        R["__mod"] = ["__mod:  JSR __divmod", "        LDA __dr", "        STA __ax",
                      "        LDA __dr+1", "        STA __ax+1", "        RTS"]
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
        R["__push"] = ["__push: LDA __csp", "        LDB #2", "        SUB",
                       "        STA __csp", "        JC __pu1", "        LDA __csp+1",
                       "        LDB #1", "        SUB", "        STA __csp+1",
                       "__pu1:  LDA __csp", "        TAP1L", "        LDA __csp+1",
                       "        TAP1H", "        LDA __ax", "        STA (P1)+",
                       "        LDA __ax+1", "        STA (P1)", "        RTS"]
        R["__enter"] = ["__enter: LDA __csp", "        LDB #2", "        SUB",
                        "        STA __csp", "        JC __en1", "        LDA __csp+1",
                        "        LDB #1", "        SUB", "        STA __csp+1",
                        "__en1:  LDA __csp", "        TAP1L", "        LDA __csp+1",
                        "        TAP1H", "        LDA __fp", "        STA (P1)+",
                        "        LDA __fp+1", "        STA (P1)",
                        "        LDA __csp", "        STA __fp",
                        "        LDA __csp+1", "        STA __fp+1", "        RTS"]
        R["__leave"] = ["__leave: LDA __fp", "        STA __csp", "        LDA __fp+1",
                        "        STA __csp+1", "        LDA __csp", "        TAP1L",
                        "        LDA __csp+1", "        TAP1H", "        LDA (P1)+",
                        "        STA __fp", "        LDA (P1)", "        STA __fp+1",
                        "        LDA __csp", "        LDB #2", "        ADD",
                        "        STA __csp", "        JNC __lv1", "        LDA __csp+1",
                        "        INC", "        STA __csp+1", "__lv1:  RTS"]
        R["__lea"] = ["__lea:  LDA __fp", "        LDB __off", "        ADD",
                      "        STA __t", "        LDA #0", "        JNC __la1",
                      "        LDA #1", "__la1:  STA __c", "        LDA __fp+1",
                      "        LDB __off+1", "        ADD", "        LDB __c",
                      "        ADD", "        STA __t+1", "        LDA __t",
                      "        TAP1L", "        LDA __t+1", "        TAP1H",
                      "        RTS"]
        R["__and"] = ["__and:  LDA __t", "        LDB __ax", "        AND",
                      "        STA __ax", "        LDA __t+1", "        LDB __ax+1",
                      "        AND", "        STA __ax+1", "        RTS"]
        R["__or"] = ["__or:   LDA __t", "        LDB __ax", "        OR",
                     "        STA __ax", "        LDA __t+1", "        LDB __ax+1",
                     "        OR", "        STA __ax+1", "        RTS"]
        R["__xor"] = ["__xor:  LDA __t", "        LDB __ax", "        XOR",
                      "        STA __ax", "        LDA __t+1", "        LDB __ax+1",
                      "        XOR", "        STA __ax+1", "        RTS"]
        # __shl/__shr: shift value __t left/right by (__ax low byte) bits -> __ax.
        R["__shl"] = ["__shl:  LDA __ax", "        STA __n", "        LDA __t",
                      "        STA __ax", "        LDA __t+1", "        STA __ax+1",
                      "__shl_l: LDA __n", "        JZ __shl_e",
                      "        LDA __ax", "        SHL", "        STA __ax",
                      "        LDA __ax+1", "        ROL", "        STA __ax+1",
                      "        LDA __n", "        DEC", "        STA __n",
                      "        JMP __shl_l", "__shl_e: RTS"]
        R["__shr"] = ["__shr:  LDA __ax", "        STA __n", "        LDA __t",
                      "        STA __ax", "        LDA __t+1", "        STA __ax+1",
                      "__shr_l: LDA __n", "        JZ __shr_e",
                      "        LDA __ax+1", "        SHR", "        STA __ax+1",
                      "        LDA __ax", "        ROR", "        STA __ax",
                      "        LDA __n", "        DEC", "        STA __n",
                      "        JMP __shr_l", "__shr_e: RTS"]
        order = ["__add", "__sub", "__mul", "__div", "__mod", "__divmod",
                 "__and", "__or", "__xor", "__shl", "__shr",
                 "__not", "__eq", "__lt", "__push", "__enter", "__leave", "__lea"]
        want = set(self.used)
        if {"__div", "__mod"} & want: want.add("__divmod")
        for h in order:
            if h in want: self.emit(*R[h])
        # __divmod uses __dr (remainder) and __t/__n; declare __dr in data
        if "__divmod" in want:
            self.data.append("__dr:   .fill 2")


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
