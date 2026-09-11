#!/usr/bin/env python3
"""p8cc - a tiny C cross-compiler for the P8X.

Emits P8X assembly (for assembler/p8xasm.py) targeting the OS transient program
area ($6A00), so the output is a RUNnable program. Grown in phases.

Supported now:
  types        int (16-bit), char (8-bit), pointers (T *), arrays (T a[N]),
               struct/union (members of any supported type, incl. nesting)
  top level    struct/union definitions, function defs w/ params, global vars
               with constant initializers (scalars, strings, {list}s, char[]
               and pointer-array tables; [] length inferred from the init)
  statements   { }  decl  if/else  while  for(e;e;e)  return [e];  expr;  ;
  expressions  =  || &&  | ^ &  == !=  < > <= >=  << >>  + - * / %
               unary - ! ~ & *   a[i]  s.m  p->m   calls(args)
               primaries: int/char/string literal, identifier, call
  struct note  structs/unions are used by pointer: NO by-value struct params,
               returns, or whole-struct assignment (assign members instead).
               union members all sit at offset 0; no bitfields, no sizeof().
  builtins     getchar()  putchar(e)  puts(e)   (OS stream syscalls $200C /
                 $2009 / $200F, so program I/O is shell-redirectable)
               peek(addr)  poke(addr,v)         (byte memory / memory-mapped I/O)
               bios(constaddr, p1, a)           (call any monitor routine: sets
                 P1=p1 and A=a, JSRs the literal addr; returns A | carry<<8)
               argstr() -> char*                (the RUN command tail, from P2)
  note         for-init is an expression, not a declaration (locals are
               function-scoped; declare the loop var before the loop)

Execution model
  * 16-bit pseudo-accumulator AX (memory word __ax) holds every expression
    result (the machine has no 16-bit accumulator).
  * Call frames live on the HARDWARE stack P3 (2026-09-11; before that a
    software C-stack __csp/__fp in RAM). The caller pushes the arguments right
    to left with PHW (each lies little-endian at P3+1), JSRs, then drops them
    with ADDP3. The callee reserves its locals with `SUBP3 #L`. Everything is
    then a small positive displacement from P3:
        locals   at P3+1 .. P3+L          (scalars first, arrays/structs above)
        return address at P3+L+1, +2
        param i  at P3+L+3+2i
    and is read/written with LDW/STW/LEAW (P3+d). The compiler tracks the
    stack depth it has pushed itself (self.sp: PHW spills, pushed args) and
    adds it to every displacement, so an expression temporary on the stack
    never moves a local. A displacement over 255 (huge local arrays) takes a
    slower computed-address path (far_local). Reentrant -> recursion works.
    On entry the program saves the caller's P3 in __sp0 and, if that P3 is
    above CSTACKTOP (a normal launch from the OS's small stack), sets P3 =
    CSTACKTOP-1 so frames grow down from $F800 into the free TPA exactly as
    the old C-stack did. A P3 already below CSTACKTOP means a NESTED launch
    (the shell running a script on a C program's stack, e.g. Finder's
    auto-return chain): then P3 is kept, so the new frames grow beneath the
    caller's instead of over it. On exit LPW3 __sp0 restores P3 before RTS.
  * char scalars occupy a 2-byte slot whose high byte is kept ZERO (stores
    write it, char params are zeroed at entry), so a char local is read with
    one LDW like an int. Globals keep static storage.
  Types are tracked so pointer arithmetic scales by element size and a
  dereference loads/stores the right width (int/pointer = 2 bytes, char = 1).

Codegen size levers (2026-09-11, -15.1% across the 45 /bin commands):
  * gen_operands: a binary op whose left operand is a LEAF (constant, string,
    global, scalar local) evaluates the RIGHT side into __ax first, then loads
    the leaf straight into __t (gen_leaf_t) -- no PHW/PLW spill pair. For a
    commutative op (+ * & | ^ == !=) with no pointer scaling a leaf on the
    right is loaded the same way; the general case still spills through P3.
  * gen_cond: if/while/for/&&/||/! conditions branch DIRECTLY on the flags of
    a 16-bit compare (__cmp16: high bytes, then low) instead of materialising
    a 0/1 in __ax and testing it: one JC/JNC/JZ/JNZ per relation, with the
    polarity folded (RELOPS table). Compares are UNSIGNED, as the value-
    producing __lt/__gt helpers always were (int is used as unsigned; see
    docs/memory). A global scalar in a condition is tested in place.
  * Runtime helpers are only emitted if named in emit_runtime's `order` list.
  Measure with `sh tools/p8cc_sizes.sh` (per-command bytes + TOTAL).

Tier A instructions (2026-09-11, a further -19.6%; -31.7% vs the pre-campaign
baseline; see docs/p8x-isa-c-extensions.md):
  * set_word_const / set_word_label: every 16-bit constant, string or global
    address is one `LDW a,#n` (4-5 bytes, was 10). The assembler picks imm8 vs
    imm16 from the literal's text, so emit plain decimals / labels.
  * gen_assign(want=False) from a statement-level `g = g +/- k` on a GLOBAL
    word (global_update_const): INCW / DECW / ADDW / SUBW on the variable in
    place -- no load, no helper, no store; pointers scale k by element size.
  * gen_cond: an ORDERING of a global word against a leaf is `CMPW g,__t` and
    one branch (C = g >= __t, the same sense as __cmp16). Never for == / != :
    CMPW's Z reflects the high byte only.
  * LPW1 for the P1 setup in bios() / puts(); `LDW __t,#k ; ADDW __ax,__t` for
    member offsets, -e, ~e (65535-e) and the post-call argument drop.
  * Frames on P3 (same day, -12.5% more; -40.3% overall): see "Execution
    model" above -- SUBP3/ADDP3 prologue/epilogue, LDW/STW/LEAW (P3+d) for
    every local, args PHW'd (little-endian on the stack since the PHW flip)
    and dropped with ADDP3; the software-frame runtime is gone.

Usage:  p8cc.py prog.c [-o prog.asm]   then  p8xasm.py prog.asm -o prog.bin --base 0x6A00
"""
import sys, os
# Single-source memory map: pull the TPA base + C-stack top from the generated
# generators/memmap.py instead of hardcoding them (see gen_memmap.py).
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "generators"))
import memmap

CSTACK_TOP = memmap.CSTACKTOP   # default; --cstacktop overrides for GUI apps
TPA_BASE   = memmap.TPABASE

# --------------------------------------------------------------------------- #
# Lexer
# --------------------------------------------------------------------------- #
KEYWORDS = {"int", "char", "void", "struct", "union",
            "if", "else", "while", "for", "return"}
PUNCT = ["==", "!=", "<=", ">=", "<<", ">>", "&&", "||", "->",
         "{", "}", "(", ")", "[", "]", ";", ",", "=", ".",
         "+", "-", "*", "/", "%", "<", ">", "!", "&", "|", "^", "~"]


def lex(src):
    toks, i, n, line = [], 0, len(src), 1
    macros = {}                            # object-like #define NAME value (value = int)
    while i < n:
        c = src[i]
        if c == "\n": line += 1; i += 1; continue
        if c in " \t\r": i += 1; continue
        if c == "#":                       # cpp directive line: only #define is honored
            eol = src.find("\n", i); eol = n if eol < 0 else eol
            parts = src[i:eol].split(None, 2)          # ['#define', NAME, 'value ...']
            if len(parts) >= 3 and parts[0] == "#define":
                vtok = parts[2].split()[0]             # first token after the name
                try:
                    macros[parts[1]] = int(vtok, 0)    # 0x.. hex or decimal
                except ValueError:
                    sys.exit("p8cc: line %d: #define %s: value %r is not an integer"
                             % (line, parts[1], vtok))
            i = eol; continue                          # (other # lines are ignored)
        if src.startswith("//", i):
            eol = src.find("\n", i); eol = n if eol < 0 else eol
            body = src[i + 2:eol].lstrip()             # "//#define NAME value" (matches //#use style)
            if body.startswith("#define"):
                parts = body.split(None, 2)
                if len(parts) >= 3:
                    try:
                        macros[parts[1]] = int(parts[2].split()[0], 0)
                    except ValueError:
                        sys.exit("p8cc: line %d: //#define %s: value %r is not an integer"
                                 % (line, parts[1], parts[2].split()[0]))
            i = eol; continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        if c.isalpha() or c == "_":
            j = i + 1
            while j < n and (src[j].isalnum() or src[j] == "_"): j += 1
            w = src[i:j]
            if w in macros:                            # object-like macro -> its number
                toks.append(("num", macros[w], line)); i = j; continue
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
        if self.val() in ("struct", "union"):
            self.next(); tag = self.next()                  # base = the tag name
            if tag[0] != "id": self.err("expected struct/union tag")
            base = tag[1]
        elif self.val() in ("int", "char", "void"):
            base = self.next()[1]
        else:
            self.err("expected a type")
        ptr = 0
        while self.accept("*"): ptr += 1
        return base, ptr

    def struct_def(self):                                   # struct/union T { ... };
        kind = self.next()[1]                               # "struct" | "union"
        tag = self.next()[1]; self.eat("{")
        members = []
        while self.val() != "}":
            base, ptr = self.base_and_ptr()
            nm = self.next()[1]; count = 0
            if self.accept("["): count = self.next()[1]; self.eat("]")
            self.eat(";")
            members.append(((base, ptr, count), nm))
        self.eat("}"); self.eat(";")
        return ("structdef", kind, tag, members)

    def toplevel(self):
        # `struct/union T {` is a type definition; otherwise it is a declaration
        # that uses the type (variable or function).
        if self.val() in ("struct", "union") and self.t[self.i + 2][1] == "{":
            return self.struct_def()
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
            if self.accept(";"):                       # prototype (forward decl)
                return ("proto", (base, ptr, 0), name, params)
            return ("func", (base, ptr, 0), name, params, self.block())
        arr = False; count = 0
        if self.accept("["):
            arr = True
            count = None if self.val() == "]" else self.next()[1]   # [] = infer
            self.eat("]")
        init = None
        if self.accept("="): init = self.initializer()
        self.eat(";")
        return ("gvar", base, ptr, arr, count, name, init)

    def initializer(self):              # constant global initializer
        if self.accept("{"):
            items = []
            if self.val() != "}":
                items.append(self.initializer())
                while self.accept(","):
                    if self.val() == "}": break              # trailing comma
                    items.append(self.initializer())
            self.eat("}")
            return ("initlist", items)
        if self.kind() == "str": return ("initstr", self.next()[1])
        neg = self.accept("-")
        if self.kind() == "num":
            v = self.next()[1]; return ("initnum", -v if neg else v)
        self.err("non-constant global initializer")

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
        if v in ("int", "char", "struct", "union"):
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
            elif self.val() == ".":
                self.next(); e = ("member", e, self.next()[1])
            elif self.val() == "->":
                self.next(); e = ("arrow", e, self.next()[1])
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
STRUCTS = {}      # tag -> {"size": n, "members": {name: (offset, base, ptr, count)}}


def sizeof(base, ptr):
    if ptr > 0 or base == "int": return 2
    if base == "char": return 1
    if base in STRUCTS: return STRUCTS[base]["size"]   # struct/union by value
    sys.exit("p8cc: unknown type %r" % base)


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
        self.sp = 0           # bytes the compiler has pushed on P3 in the current expression
        self.frame = 0        # L: bytes of locals reserved by SUBP3 in the current function
        self.uses_la = False  # far_local scratch words __la/__lb needed

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

    def struct_member(self, tag, mname):      # -> (offset, base, ptr, count)
        if tag not in STRUCTS: sys.exit("p8cc: not a struct/union: %r" % tag)
        ms = STRUCTS[tag]["members"]
        if mname not in ms:
            sys.exit("p8cc: %r has no member %r" % (tag, mname))
        return ms[mname]

    def member_tag(self, e):                  # struct tag of a `.`/`->` target
        if e[0] == "member": return self.typeof_lval(e[1])[0]    # x.m  -> tag of x
        return self.typeof(e[1])[0]                              # p->m -> tag *p points to

    def typeof(self, e):                      # -> (base, ptr) of e's value (arrays decay)
        k = e[0]
        if k == "num": return ("int", 0)
        if k in ("member", "arrow"):
            _, mb, mp, mc = self.struct_member(self.member_tag(e), e[2])
            return (mb, mp + 1) if mc else (mb, mp)             # array member decays
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
        if e[0] in ("member", "arrow"):
            _, mb, mp, _ = self.struct_member(self.member_tag(e), e[2])
            return (mb, mp)
        sys.exit("p8cc: not an lvalue")

    # ---- helpers ------------------------------------------------------------
    # ---- frame locals on the hardware stack ---------------------------------
    # A local's frame offset is fixed; its DISPLACEMENT from P3 right now is that
    # plus whatever the compiler has pushed since the prologue (self.sp).
    def local_disp(self, off): return off + self.sp
    def far_local(self, d):                   # __la = P3 + d, for d > 255 (rare)
        self.uses_la = True
        self.emit("        TPA3L", "        STA __la", "        TPA3H", "        STA __la+1")
        if d <= 255: self.emit("        ADDW __la,#%d" % d)
        else: self.emit("        LDW __lb,#%d" % d, "        ADDW __la,__lb")
    def ld_local(self, dst, off):             # dst (word) = the frame slot (chars: zero-high slot)
        d = self.local_disp(off)
        if d <= 255: self.emit("        LDW %s,(P3+%d)" % (dst, d)); return
        self.far_local(d)
        self.emit("        LPW1 __la", "        LDA (P1)+", "        STA %s" % dst,
                  "        LDA (P1)", "        STA %s+1" % dst)
    def st_local(self, off, full):            # frame slot = __ax; full=False: low byte + zero high
        d = self.local_disp(off)
        if full:
            if d <= 255: self.emit("        STW (P3+%d),__ax" % d); return
            self.far_local(d)
            self.emit("        LPW1 __la", "        LDA __ax", "        STA (P1)+",
                      "        LDA __ax+1", "        STA (P1)"); return
        if d <= 254:
            self.emit("        LDA __ax", "        STA (P3+%d)" % d,
                      "        LDA #0", "        STA (P3+%d)" % (d + 1)); return
        self.far_local(d)
        self.emit("        LPW1 __la", "        LDA __ax", "        STA (P1)+",
                  "        LDA #0", "        STA (P1)")
    def lea_local(self, off):                 # __ax = address of the frame slot
        d = self.local_disp(off)
        if d <= 255: self.emit("        LEAW __ax,(P3+%d)" % d); return
        self.far_local(d); self.mov16("__ax", "__la")
    def zero_hi_local(self, off):             # slot's high byte := 0 (char params at entry)
        d = self.local_disp(off) + 1
        if d <= 255: self.emit("        LDA #0", "        STA (P3+%d)" % d); return
        self.far_local(d); self.emit("        LPW1 __la", "        LDA #0", "        STA (P1)")
    def adj_sp(self, n, up):                  # P3 += n (drop) / -= n (reserve), in imm8 chunks
        self.sp -= n if up else -n
        while n > 0:
            k = min(n, 255); n -= k
            self.emit("        %s #%d" % ("ADDP3" if up else "SUBP3", k))
    def char_load(self, e):                   # e is a LOAD of a char: its high byte is 0
        return (self.typeof(e) == ("char", 0) and
                (e[0] in ("id", "index", "member", "arrow") or
                 (e[0] == "unary" and e[1] == "*")))

    # Tier A: a 16-bit constant into a memory word is ONE instruction -- `LDW a,#n`
    # (4 bytes for 0..255, zero-extended; 5 bytes otherwise; the assembler picks
    # the width from the literal's text). Was LDA #lo/STA/LDA #hi/STA: 10 bytes,
    # and the single most frequent idiom in compiled code.
    def set_word_const(self, dst, v):
        self.emit("        LDW %s,#%d" % (dst, v & 0xFFFF))
    def set_word_label(self, dst, lab):                  # a 16-bit address constant
        self.emit("        LDW %s,#%s" % (dst, lab))
    def set_ax_const(self, v): self.set_word_const("__ax", v)

    def mov16(self, dst, src):                          # 16-bit mem->mem (was LDA/STA x2)
        self.emit("        MOVW %s,%s" % (dst, src))
    def push_ax(self): self.emit("        PHW __ax"); self.sp += 2   # 16-bit push (tracked)
    def pop_t(self): self.emit("        PLW __t"); self.sp -= 2       # 16-bit pop

    def ax_to_p1(self): self.emit("        LPW1 __ax")   # P1 = word @ __ax (was LDA/TAP1L/LDA/TAP1H)

    # ---- leaf operands: straight into __t, skipping the PHW/PLW spill -----------
    # Every binary helper computes  __t OP __ax  (left in __t, right in __ax). The
    # old idiom evaluated the left into __ax, PUSHED it, evaluated the right, then
    # POPPED the left into __t: 6 bytes and two stack round-trips per operator. When
    # a side is a LEAF (a constant, a string, a scalar variable, a global array's
    # address) it can be loaded into __t directly, after the other side is already
    # sitting in __ax -- so: right side first (it may clobber __t), leaf last.
    COMMUTATIVE = ("+", "*", "&", "|", "^", "==", "!=")
    def is_leaf(self, e):
        if e[0] in ("num", "str"): return True
        if e[0] != "id": return False
        kind = self.vinfo(e[1])
        return kind[0] == "g" or not kind[4]      # any global; a local only if scalar
    def gen_leaf_t(self, e):                          # __t = value of a leaf
        k = e[0]
        if k == "num":
            self.set_word_const("__t", e[1])
        elif k == "str":
            self.set_word_label("__t", self.string(e[1]))
        else:
            kind = self.vinfo(e[1])
            base, ptr, count = kind[2], kind[3], kind[4]
            if count:                                  # a global array: its address
                self.set_word_label("__t", kind[1])
            elif kind[0] == "l":                       # scalar local: one LDW (P3+d)
                self.ld_local("__t", kind[1])
            elif sizeof(base, ptr) == 2:
                self.mov16("__t", kind[1])
            else:
                self.emit("        LDA %s" % kind[1], "        STA __t",
                          "        LDA #0", "        STA __t+1")
    def gen_operands(self, op, lhs, rhs, scale=0):
        """Leave lhs in __t and rhs (scaled by `scale` if 2) in __ax for a helper.
        Uses the direct-leaf path when it can; the push/pop spill only otherwise."""
        def scale_ax():
            if scale == 2:
                self.emit("        LDA __ax", "        SHL", "        STA __ax",
                          "        LDA __ax+1", "        ROL", "        STA __ax+1")
        if self.is_leaf(lhs):                         # right first, leaf into __t last
            self.gen_expr(rhs); scale_ax(); self.gen_leaf_t(lhs)
        elif scale == 0 and op in self.COMMUTATIVE and self.is_leaf(rhs):
            self.gen_expr(lhs); self.gen_leaf_t(rhs)  # operands swapped: op commutes
        else:
            self.gen_expr(lhs); self.push_ax()
            self.gen_expr(rhs); scale_ax()
            self.pop_t()

    def add_const_ax(self, off):              # AX += off (16-bit constant)
        off &= 0xFFFF
        if off == 0: return
        # Tier A: `LDW __t,#off ; ADDW __ax,__t` (9-10 bytes) replaces a 20-byte
        # inline carry-propagating add. __t is free here: it is only ever live
        # between a leaf load and the helper JSR that follows it (gen_operands).
        self.set_word_const("__t", off)
        self.emit("        ADDW __ax,__t")

    # ---- addresses (lvalues): result address in __ax -----------------------
    def gen_address(self, e):
        k = e[0]
        if k == "id":
            kind = self.vinfo(e[1])
            if kind[0] == "l": self.lea_local(kind[1])   # __ax = P3 + d (LEAW)
            else: self.set_word_label("__ax", kind[1])
        elif k == "unary" and e[1] == "*":
            self.gen_expr(e[2])                          # AX = pointer value = address
        elif k == "member":                              # &(x.m) = &x + offset
            off = self.struct_member(self.member_tag(e), e[2])[0]
            self.gen_address(e[1]); self.add_const_ax(off)
        elif k == "arrow":                               # &(p->m) = p + offset
            off = self.struct_member(self.member_tag(e), e[2])[0]
            self.gen_expr(e[1]); self.add_const_ax(off)
        elif k == "index":                               # &a[i] = base + i*elemsize
            b, p = self.typeof(e[1]); esz = sizeof(b, p - 1)   # typeof is the decayed ptr
            self.gen_operands("+", e[1], e[2], 2 if esz == 2 else 0)   # __t=base __ax=i
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
            self.set_word_label("__ax", self.string(e[1]))
        elif k == "id":
            kind = self.vinfo(e[1])
            base, ptr, count = kind[2], kind[3], kind[4]
            if count:                                    # array decays to its address
                self.gen_address(e)
            elif kind[0] == "l":                         # local word, or a char's
                if sizeof(base, ptr) not in (1, 2):      # zero-high 2-byte slot
                    sys.exit("p8cc: struct/union %r used as a value" % e[1])
                self.ld_local("__ax", kind[1])
            else:
                lab = kind[1]
                if sizeof(base, ptr) == 2:
                    self.mov16("__ax", lab)              # 16-bit var load -> AX
                else:
                    self.emit("        LDA %s" % lab, "        STA __ax",
                              "        LDA #0", "        STA __ax+1")
        elif k == "unary":
            if e[1] == "&": self.gen_address(e[2])
            elif e[1] == "*":
                self.gen_expr(e[2]); self.load_deref(*self.typeof_lval(e))
            elif e[1] == "!":
                self.gen_expr(e[2]); self.need("__not"); self.emit("        JSR __not")
            elif e[1] == "~":                                # bitwise NOT = 65535 - e
                self.gen_expr(e[2]); self.need("__sub")
                self.set_word_const("__t", 0xFFFF)
                self.emit("        JSR __sub")                 # __ax = __t - __ax
            else:  # -e = 0 - e
                self.gen_expr(e[2]); self.need("__sub")
                self.set_word_const("__t", 0)
                self.emit("        JSR __sub")
        elif k == "index":
            self.gen_address(e); self.load_deref(*self.typeof_lval(e))
        elif k in ("member", "arrow"):
            mc = self.struct_member(self.member_tag(e), e[2])[3]
            if mc: self.gen_address(e)                   # array member decays to address
            else: self.gen_address(e); self.load_deref(*self.typeof_lval(e))
        elif k == "assign": self.gen_assign(e[1], e[2], want=True)
        elif k == "logand": self.gen_logand(e[1], e[2])
        elif k == "logor": self.gen_logor(e[1], e[2])
        elif k == "bin": self.gen_bin(e[1], e[2], e[3])
        elif k == "call": self.gen_call(e[1], e[2])
        else: sys.exit("p8cc: cannot generate expr %r" % (k,))

    def global_update_const(self, lhs, rhs):
        """`g = g + k` / `g = g - k` on a GLOBAL word scalar -> the constant the
        word must change by (element-scaled for pointers), or None if the
        statement is not of that shape. Tier A turns it into INCW/DECW/ADDW/SUBW
        on the variable in place: no load, no helper call, no store."""
        if rhs[0] != "bin" or rhs[1] not in ("+", "-"): return None
        if rhs[2] != lhs or lhs[0] != "id" or rhs[3][0] != "num": return None
        kind = self.vinfo(lhs[1])
        if kind[0] != "g" or kind[4] or sizeof(kind[2], kind[3]) != 2: return None
        base, ptr = self.typeof(lhs)
        step = sizeof(base, ptr - 1) if ptr > 0 else 1   # pointer: scale by element
        k = (rhs[3][1] * step) & 0xFFFF
        return k if rhs[1] == "+" else (-k) & 0xFFFF

    def gen_assign(self, lhs, rhs, want=True):
        """Store rhs into lhs. `want`: the assignment's VALUE is needed in __ax
        (expression context); a statement-level `x = ...;` passes False and can
        update a global in place with the Tier A memory ops."""
        sz = sizeof(*self.typeof_lval(lhs))
        if sz not in (1, 2):
            sys.exit("p8cc: whole struct/array assignment not supported "
                     "(assign members, or use pointers)")
        k = self.global_update_const(lhs, rhs)
        if k is not None:
            lab = self.vinfo(lhs[1])[1]
            if k == 1: self.emit("        INCW %s" % lab)
            elif k == 0xFFFF: self.emit("        DECW %s" % lab)
            elif k < 0x8000:
                self.set_word_const("__t", k); self.emit("        ADDW %s,__t" % lab)
            else:
                self.set_word_const("__t", (-k) & 0xFFFF); self.emit("        SUBW %s,__t" % lab)
            if want: self.mov16("__ax", lab)
            return
        # fast path: `var = expr` for a plain scalar variable (not an array,
        # deref, member or index). Compute the value into AX, then store it with
        # one instruction/helper — AX is left holding the value (assignment result).
        if lhs[0] == "id":
            kind = self.vinfo(lhs[1])
            if not kind[4]:                              # count==0: not an array
                self.gen_expr(rhs)                       # AX = value
                if kind[0] == "l":                       # local -> (P3+d); a char slot
                    self.st_local(kind[1], sz == 2 or self.char_load(rhs))   # keeps hi=0
                elif sz == 2:                            # global word -> fixed label
                    self.mov16(kind[1], "__ax")          # MOVW lab,__ax
                else:                                    # global byte
                    self.emit("        LDA __ax", "        STA %s" % kind[1])
                return
        self.gen_expr(rhs); self.push_ax()               # value on P3
        self.gen_address(lhs)                            # AX = dest address
        self.ax_to_p1()                                  # P1 = dest
        self.pop_t()                                     # __t = value
        if sz == 2:
            self.emit("        LDA __t", "        STA (P1)+",
                      "        LDA __t+1", "        STA (P1)")
        else:
            self.emit("        LDA __t", "        STA (P1)")
        self.mov16("__ax", "__t")                        # assignment yields the value

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
        self.gen_operands(op, lhs, rhs, scale)            # __t = lhs, __ax = rhs (scaled)
        self.need(helper); self.emit("        JSR %s" % helper)
        if neg:
            self.need("__not"); self.emit("        JSR __not")

    def gen_logand(self, a, b):                          # && as a 0/1 VALUE
        f = self.lbl("Land0"); end = self.lbl("Lande")
        self.gen_cond(a, f, False); self.gen_cond(b, f, False)
        self.emit("        LDA #1", "        STA __ax", "        LDA #0",
                  "        STA __ax+1", "        JMP %s" % end,
                  "%s:    LDA #0" % f, "        STA __ax", "        STA __ax+1",
                  "%s:" % end)

    def gen_logor(self, a, b):                           # || as a 0/1 VALUE
        t = self.lbl("Lor1"); end = self.lbl("Lore")
        self.gen_cond(a, t, True); self.gen_cond(b, t, True)
        self.emit("        LDA #0", "        STA __ax", "        STA __ax+1",
                  "        JMP %s" % end,
                  "%s:    LDA #1" % t, "        STA __ax", "        LDA #0",
                  "        STA __ax+1", "%s:" % end)

    # ---- conditions: branch on the truth of an expression, no 0/1 in __ax --------
    # `if (a < b)` used to be: spill, JSR __lt (builds a 0/1 word), OR, JZ -- 16
    # bytes and a runtime call. A comparison in CONDITION context now emits its two
    # operands (leaf path when possible), `JSR __cmp16` (which leaves the FLAGS:
    # C = left>=right unsigned, Z = left==right) and ONE direct branch: 6 bytes.
    # `<` stays UNSIGNED, exactly as __lt was -- p8cc's int is used as unsigned and
    # that ordering is load-bearing (a signed `<` once shipped a buffer overflow).
    # && / || / ! short-circuit through the same path.
    RELOPS = {"<": (False, False), ">": (True, False), "<=": (True, True),
              ">=": (False, True), "==": (False, False), "!=": (False, True)}
    def gen_cond(self, e, label, when):
        """Jump to label if (truth of e) == when, else fall through."""
        k = e[0]
        if k == "bin" and e[1] in self.RELOPS:
            swap, neg = self.RELOPS[e[1]]
            a, b = e[2], e[3]
            lhs, rhs = (b, a) if swap else (a, b)
            # Tier A: an ORDERING of a global word against a leaf compares the
            # variable in place -- `CMPW lab,__t` sets C = lab >= __t exactly as
            # __cmp16 sets C = lhs >= rhs, with no load of the left side. Not for
            # == / != : CMPW's Z reflects the high byte only.
            if (e[1] not in ("==", "!=") and lhs[0] == "id" and self.is_leaf(rhs)
                    and self.vinfo(lhs[1])[0] == "g" and not self.vinfo(lhs[1])[4]
                    and sizeof(self.vinfo(lhs[1])[2], self.vinfo(lhs[1])[3]) == 2):
                self.gen_leaf_t(rhs)
                self.emit("        CMPW %s,__t" % self.vinfo(lhs[1])[1])
                self.emit("        %s %s" % ("JC" if neg == when else "JNC", label))
                return
            self.gen_operands(e[1], lhs, rhs, 0)      # __t = lhs, __ax = rhs
            self.need("__cmp16"); self.emit("        JSR __cmp16")
            if e[1] in ("==", "!="):                  # truth = Z (==) or !Z (!=)
                jz = ((e[1] == "==") == when)
                self.emit("        %s %s" % ("JZ" if jz else "JNZ", label))
            else:                                     # truth = (lhs<rhs) xor neg = (C==neg)
                jc = (neg == when)
                self.emit("        %s %s" % ("JC" if jc else "JNC", label))
            return
        if k == "unary" and e[1] == "!":
            self.gen_cond(e[2], label, not when); return
        if k == "logand":
            if not when:
                self.gen_cond(e[1], label, False); self.gen_cond(e[2], label, False)
            else:
                f = self.lbl("Lca")
                self.gen_cond(e[1], f, False); self.gen_cond(e[2], label, True)
                self.emit("%s:" % f)
            return
        if k == "logor":
            if when:
                self.gen_cond(e[1], label, True); self.gen_cond(e[2], label, True)
            else:
                t = self.lbl("Lco")
                self.gen_cond(e[1], t, True); self.gen_cond(e[2], label, False)
                self.emit("%s:" % t)
            return
        if k == "id":                                     # a global scalar: test in place
            kind = self.vinfo(e[1])
            base, ptr, count = kind[2], kind[3], kind[4]
            if kind[0] == "g" and not count:
                j = "JNZ" if when else "JZ"
                if sizeof(base, ptr) == 2:
                    self.emit("        LDA %s" % kind[1], "        LDB %s+1" % kind[1],
                              "        OR", "        %s %s" % (j, label))
                else:
                    self.emit("        LDA %s" % kind[1], "        %s %s" % (j, label))
                return
        self.gen_expr(e)                                  # general case: value, then test
        self.emit("        LDA __ax", "        LDB __ax+1", "        OR",
                  "        %s %s" % ("JNZ" if when else "JZ", label))

    def gen_call(self, name, args):
        if name == "getchar":                            # OS SYS_GETC -> char, or -1 at EOF
            skip = self.lbl("Lge")
            self.emit("        JSR $200C", "        STA __ax",
                      "        LDA #0", "        STA __ax+1",
                      "        JNC %s" % skip,             # carry = end of (file) input
                      "        LDW __ax,#65535",           # __ax = $FFFF (-1)
                      "%s:" % skip); return
        if name == "putchar":                            # OS SYS_PUTC (redirectable)
            self.gen_expr(args[0])
            self.emit("        LDA __ax", "        JSR $2009"); return
        if name == "puts":                               # OS SYS_PUTS + newline
            self.gen_expr(args[0]); self.ax_to_p1()      # P1 = the string (LPW1)
            self.emit("        JSR $200F",
                      "        LDA #10", "        JSR $2009"); return
        if name == "peek":                               # peek(addr) -> byte at addr
            self.gen_expr(args[0]); self.ax_to_p1()
            self.emit("        LDA (P1)", "        STA __ax",
                      "        LDA #0", "        STA __ax+1"); return
        if name == "poke":                               # poke(addr, val)
            self.gen_expr(args[1]); self.push_ax()
            self.gen_expr(args[0]); self.ax_to_p1()
            self.pop_t()
            self.emit("        LDA __t", "        STA (P1)"); return
        if name == "argstr":                             # P2 (program arg tail) -> char*
            self.emit("        TPA2L", "        STA __ax",
                      "        TPA2H", "        STA __ax+1"); return
        if name == "bios":                               # bios(addr, p1, a) -> A | carry<<8
            if args[0][0] != "num":
                sys.exit("p8cc: bios() address must be a constant")
            self.gen_expr(args[1]); self.push_ax()       # P1 operand
            self.gen_expr(args[2])                        # A operand -> __ax
            self.pop_t()                                  # __t = P1 operand
            skip = self.lbl("Lbc")
            self.emit("        LPW1 __t",                  # P1 = arg1
                      "        LDA __ax", "        JSR $%04X" % (args[0][1] & 0xFFFF),
                      "        STA __ax",                  # returned A -> low byte
                      "        LDA #0", "        JNC %s" % skip, "        LDA #1",
                      "%s:    STA __ax+1" % skip); return  # carry -> bit 8
        for a in reversed(args):                         # args right to left onto P3:
            self.gen_expr(a); self.push_ax()             # the leftmost ends nearest SP
        self.emit("        JSR _f_%s" % name)
        if args: self.adj_sp(2 * len(args), up=True)     # drop them: ADDP3 #2n

    # ---- statements ---------------------------------------------------------
    def gen_stmt(self, s):
        k = s[0]
        assert self.sp == 0, "p8cc: unbalanced stack depth %d before a statement" % self.sp
        if k == "block":
            for st in s[1]: self.gen_stmt(st)
        elif k == "decl":
            if s[3] is not None:
                self.gen_assign(("id", s[2]), s[3])
        elif k == "expr":
            if s[1][0] == "assign":                      # statement: value unused
                self.gen_assign(s[1][1], s[1][2], want=False)
            else: self.gen_expr(s[1])
        elif k == "empty": pass
        elif k == "return":
            if s[1] is not None: self.gen_expr(s[1])
            self.emit("        JMP _ret_%s" % self.func)
        elif k == "if":
            els = self.lbl("Lelse"); end = self.lbl("Lend")
            self.gen_cond(s[1], els if s[3] else end, False)
            self.gen_stmt(s[2])
            if s[3]:
                self.emit("        JMP %s" % end, "%s:" % els)
                self.gen_stmt(s[3])
            self.emit("%s:" % end)
        elif k == "while":
            top = self.lbl("Ltop"); end = self.lbl("Lend")
            self.emit("%s:" % top)
            self.gen_cond(s[1], end, False)
            self.gen_stmt(s[2])
            self.emit("        JMP %s" % top, "%s:" % end)
        elif k == "for":                                  # for(init; cond; post) body
            init, cond, post, body = s[1], s[2], s[3], s[4]
            top = self.lbl("Ltop"); end = self.lbl("Lend")
            if init is not None: self.gen_expr(init)
            self.emit("%s:" % top)
            if cond is not None: self.gen_cond(cond, end, False)
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

    def local_size(self, base, ptr, count):    # bytes a local/global occupies
        if count: return count * sizeof(base, ptr)
        if ptr == 0 and base in STRUCTS: return STRUCTS[base]["size"]
        return 2                                # scalar/pointer: one 2-byte slot

    def compile_func(self, name, params, body):
        self.func = name; self.locals = {}; self.sp = 0
        pnames = set()
        for (base, ptr, _), pnm in params:
            if ptr == 0 and base in STRUCTS:
                sys.exit("p8cc: struct/union passed by value (%r) not supported; "
                         "pass a pointer" % pnm)
            pnames.add(pnm)
        # Frame layout (see the header): locals at P3+1.., SCALARS FIRST so the
        # hot variables always sit inside the 255-byte displacement window and
        # arrays/structs stack above them; then the return address; then params.
        seen = set(); scalars = []; aggregates = []
        for d in self.collect_decls(body):
            (base, ptr, count), nm = d[1], d[2]
            if nm in pnames or nm in seen: continue         # first declaration wins
            seen.add(nm)
            (aggregates if (count or (ptr == 0 and base in STRUCTS)) else scalars) \
                .append((nm, base, ptr, count))
        off = 1
        for nm, base, ptr, count in scalars + aggregates:
            self.locals[nm] = (off, base, ptr, count)
            off += self.local_size(base, ptr, count)
        L = off - 1; self.frame = L
        for i, ((base, ptr, _), pnm) in enumerate(params):
            self.locals[pnm] = (L + 3 + 2 * i, base, ptr, 0)   # above the return address
        self.emit("_f_%s:" % name)
        if L: self.adj_sp(L, up=False); self.sp = 0     # SUBP3 #L reserves the locals
        for (base, ptr, _), pnm in params:               # char params: the caller pushed a
            if sizeof(base, ptr) == 1:                    # full int -> keep the slot's high
                self.zero_hi_local(self.locals[pnm][0])  # byte 0 (char semantics)
        self.gen_stmt(body)
        self.emit("_ret_%s:" % name)
        if L: self.adj_sp(L, up=True); self.sp = 0       # ADDP3 #L frees them
        self.emit("        RTS")

    def declare_global(self, base, ptr, arr, count, name, init):
        lab = "_g_" + name; esz = sizeof(base, ptr)
        if arr and count is None:                       # infer [] length from init
            if init is None: sys.exit("p8cc: array %r needs a size or initializer" % name)
            if init[0] == "initstr" and base == "char" and ptr == 0:
                count = len(init[1]) + 1                 # + NUL
            elif init[0] == "initlist": count = len(init[1])
            else: sys.exit("p8cc: cannot infer size of %r" % name)
        self.globals[name] = (lab, base, ptr, count if arr else 0)
        if init is None:
            total = (count * esz) if arr else esz
            self.data.append("%s:    .fill %d" % (lab, total)); return
        # Build the data first: const_data may pool string literals into
        # self.data, which must land BEFORE this label so the label is
        # immediately followed by its own bytes (not an interleaved string).
        lines = self.const_data(base, ptr, arr, count, init)
        self.data.append("%s:" % lab)
        self.data.extend(lines)

    def const_data(self, base, ptr, arr, count, init):  # -> asm data lines
        esz = sizeof(base, ptr); out = []
        word = lambda x: out.append("        .word %s" % x)
        byte = lambda x: out.append("        .byte %s" % x)
        if not arr:                                      # scalar global
            if init[0] == "initstr":
                if ptr == 0: sys.exit("p8cc: string initializer for non-pointer")
                word(self.string(init[1]))
            elif init[0] == "initnum":
                (word if esz == 2 else byte)(init[1])
            else: sys.exit("p8cc: brace initializer for scalar")
            return out
        if base == "char" and ptr == 0 and init[0] == "initstr":   # char s[] = "..."
            bs = list(init[1])[:count] + [0] * max(0, count - len(init[1]))
            out.append("        .byte " + ",".join(str(b) for b in bs[:count])); return out
        if init[0] != "initlist":
            sys.exit("p8cc: array needs a brace initializer or string")
        items = init[1]
        if len(items) > count: sys.exit("p8cc: too many initializers")
        for it in items:
            if it[0] == "initstr":
                if ptr == 0: sys.exit("p8cc: string initializer for non-pointer element")
                word(self.string(it[1]))
            elif it[0] == "initnum":
                (word if esz == 2 else byte)(it[1])
            else: sys.exit("p8cc: nested brace initializer not supported")
        rem = count - len(items)
        if rem: out.append("        .fill %d" % (rem * esz))    # zero-pad the tail
        return out

    def register_struct(self, kind, tag, members):
        # struct: members laid out sequentially; union: all at offset 0.
        off = 0; size = 0; m = {}
        for (base, ptr, count), nm in members:
            sz = (count * sizeof(base, ptr)) if count else sizeof(base, ptr)
            m[nm] = (0 if kind == "union" else off, base, ptr, count)
            if kind == "union": size = max(size, sz)
            else: off += sz
        STRUCTS[tag] = {"size": (size if kind == "union" else off), "members": m}

    def gen_program(self, decls):
        STRUCTS.clear()
        for d in decls:                                 # struct/union layouts first
            if d[0] == "structdef": self.register_struct(d[1], d[2], d[3])
        for d in decls:
            if d[0] in ("func", "proto"):               # prototypes declare too
                self.funcs[d[2]] = (d[1][0], d[1][1])   # name -> return (base, ptr)
        for d in decls:
            if d[0] == "gvar":
                _, base, ptr, arr, count, name, init = d
                self.declare_global(base, ptr, arr, count, name, init)
        # Startup: keep the caller's stack pointer, run main on a stack growing
        # down from CSTACKTOP (where the old software C-stack lived), restore, RTS.
        # Relocate ONLY when the inherited P3 is above CSTACKTOP, i.e. a normal
        # launch from the OS's 256-byte stack. A program launched while the shell
        # is already running on a C program's stack (Finder -> SYS_RUNSH -> `run`)
        # inherits a P3 BELOW CSTACKTOP; moving it up to CSTACKTOP-1 would put our
        # frames on top of the caller's pending return addresses -- so keep it and
        # grow down from there instead.
        self.emit("        .org $%04X" % TPA_BASE,
                  "        TPA3L", "        STA __sp0", "        TPA3H", "        STA __sp0+1",
                  "        LDB #%d" % (CSTACK_TOP >> 8), "        CMP",   # A = P3.hi
                  "        JNC __sk0",                                    # P3 < CSTACKTOP: nested launch, keep
                  "        LDP3 #%d" % ((CSTACK_TOP - 1) & 0xFFFF),
                  "__sk0:  JSR _f_main",
                  "        LPW3 __sp0", "        RTS")
        for d in decls:
            if d[0] == "func": self.compile_func(d[2], d[3], d[4])
        self.emit_runtime()
        self.emit("__ax:   .fill 2", "__t:    .fill 2", "__c:    .fill 1",
                  "__sp0:  .fill 2")
        if self.uses_la: self.emit("__la:   .fill 2", "__lb:   .fill 2")
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
                      "        MOVW __ax,__r", "        RTS"]
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
        R["__div"] = ["__div:  JSR __divmod", "        MOVW __ax,__t", "        RTS"]
        R["__mod"] = ["__mod:  JSR __divmod", "        MOVW __ax,__dr", "        RTS"]
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
        # (The software-frame runtime -- __push/__enter/__entf/__leave/__lea/
        # __ldw/__ldb/__ldtw/__ldtb/__stw/__stb -- is gone: frames live on P3 and
        # every local access is one LDW/STW/LEAW (P3+d) instruction, 2026-09-11.)
        # __cmp16: compare __t (left) with __ax (right) as 16-bit UNSIGNED and leave
        # the FLAGS for a direct branch: C = left>=right, Z = left==right. High bytes
        # first; only when they are equal does the low-byte compare decide -- so C
        # and Z are both right for the full 16 bits. Replaces __lt + __not + OR/JZ in
        # condition context (gen_cond). Unsigned on purpose, matching __lt.
        R["__cmp16"] = ["__cmp16: LDA __t+1", "        LDB __ax+1", "        CMP",
                        "        JNZ __cmp16r", "        LDA __t", "        LDB __ax",
                        "        CMP", "__cmp16r: RTS"]
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
                 "__not", "__eq", "__lt", "__cmp16"]
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
    global CSTACK_TOP
    a = sys.argv[1:]
    if not a: sys.exit("usage: p8cc.py prog.c [-o out] [--cstacktop N]")
    src_path = a[0]; out = "a.asm"
    if "-o" in a: out = a[a.index("-o") + 1]
    if "--cstacktop" in a:              # GUI apps link BELOW a resident WM
        CSTACK_TOP = int(a[a.index("--cstacktop") + 1], 0)
    open(out, "w").write(compile_src(open(src_path).read()))
    print("p8cc: %s -> %s" % (src_path, out))


if __name__ == "__main__":
    main()
