#!/usr/bin/env python3
"""tierA_rewrite.py -- mechanical first pass for moving hand-written P8X
assembly onto the Tier A ISA (2026-09-12).

    python3 tools/tierA_rewrite.py FILE.asm            # dry run: list every match
    python3 tools/tierA_rewrite.py FILE.asm --apply    # rewrite in place
    python3 tools/tierA_rewrite.py FILE.asm --allow JSR:EMIT,EMSY   # callees that
                                                       # do not read A (see below)

It replaces the byte-by-byte 16-bit idioms hand assembly grew before the word
instructions existed, one idiom -> one instruction:

    LDA x / STA y / LDA x+1 / STA y+1          ->  MOVW y,x
    LDA #lo / STA y / LDA #hi / STA y+1        ->  LDW y,#n        (also #<s / #>s -> #s)
    LDA #0 / STA y / STA y+1                   ->  LDW y,#0
    LDA x / TAPnL / LDA x+1 / TAPnH            ->  LPWn x          (n = 1, 2)
    LDA #<s / TAPnL / LDA #>s / TAPnH          ->  LDPn #s         (n = 1, 2, 3)
    LDA x / INC / STA x / JNZ L / LDA x+1 / INC / STA x+1 / L:            -> INCW x
    LDA x / LDB #1 / ADD / STA x / JNC L / LDA x+1 / INC / STA x+1 / L:   -> INCW x
    LDA x / LDB #k / ADD / STA x / JNC L / LDA x+1 / INC / STA x+1 / L:   -> ADDW x,#k
    LDA x / LDB #1 / SUB / STA x / JC L / LDA x+1 / DEC / STA x+1 / L:    -> DECW x
    (the carry-fix chains also match when the tail is `JMP L` instead of `L:`)

THE SAFETY RULE. The old sequence leaves A = the high byte (or the ALU result)
and Z/N/C from its last operation; the word instruction leaves A and the flags
differently (MOVW/LDW/LPWn/LDPn touch neither; ADDW/INCW... clobber A and set
their own flags). A site is rewritten only when the NEXT instruction executed
cannot observe that: a load into A/B/T/Pn (LDA LDB LDT LDPn LPWn PLA PLW TPAxx),
another word op (LDW STW MOVW ADDW SUBW CMPW ANDW ORW XORW INCW DECW LEAW PHW
ADDP3 SUBP3), INPn/DEPn, RTS/RTI/HLT/NOP, or a JSR/JMP whose target is known not
to read A (JSR callees must be named with --allow; a JMP is followed one hop to
its target's first instruction). Anything else -- STA, PHA, an ALU op, CMP,
TAPn, a conditional branch -- keeps the original bytes. A label between the
sequence and the next instruction is skipped over (the check applies to the
instruction that actually runs). An INTERNAL label (the `L:` a carry-fix chain
jumps over) must be referenced exactly once in the file, or the chain is kept.

Everything it emits is a shape the NATIVE assembler parses too (no relative
branches), so rewritten sources stay byte-identical between the two
assemblers. Always follow a run with the module's tests: the rule is
conservative but the callee allow-list is the operator's judgement.
"""
import re, sys

SAFE_NEXT = {"LDA", "LDB", "LDT", "LDP1", "LDP2", "LDP3", "LPW1", "LPW2", "LPW3", "PLA", "PLW",
             "TPA1L", "TPA1H", "TPA2L", "TPA2H", "TPA3L", "TPA3H",
             "LDW", "STW", "MOVW", "ADDW", "SUBW", "CMPW", "ANDW", "ORW", "XORW", "INCW", "DECW",
             "LEAW", "PHW", "ADDP3", "SUBP3", "INP1", "INP2", "INP3", "DEP1", "DEP2", "DEP3",
             "RTS", "RTI", "HLT", "NOP", "EI", "DI"}


class Line:
    def __init__(self, idx, text):
        self.idx = idx; self.text = text
        code = text.split(";")[0].rstrip()
        self.label = None; self.mn = None; self.opnd = ""
        if code.strip():
            if not code[0].isspace():
                lab, _, rest = code.partition(":")
                self.label = lab.strip(); code = rest
            t = code.split(None, 1)
            if t:
                self.mn = t[0].upper()
                self.opnd = t[1].strip() if len(t) > 1 else ""
                if self.mn.startswith("."): self.mn = None   # directive: opaque


def load(path):
    return [Line(i, l) for i, l in enumerate(open(path, errors="replace").read().split("\n"))]


def is_lit(t):
    return re.fullmatch(r"\$[0-9A-Fa-f]+|\d+|'.'", t) is not None


def lit(t):
    if t.startswith("$"): return int(t[1:], 16)
    if t.startswith("'"): return ord(t[1])
    return int(t)


class Rewriter:
    def __init__(self, lines, allow_jsr):
        self.L = lines
        self.ins = [l for l in lines if l.mn]           # instruction view
        self.pos = {id(l): k for k, l in enumerate(self.ins)}
        self.allow_jsr = allow_jsr
        self.labels = {}                                 # label -> index in self.ins of first instr at/after it
        self.refs = {}                                   # label -> reference count (operands)
        for k, l in enumerate(self.ins):
            pass
        cur = []
        for l in lines:
            if l.label: cur.append(l.label)
            if l.mn:
                for lab in cur: self.labels[lab] = self.pos[id(l)]
                cur = []
                for tok in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", l.opnd):
                    self.refs[tok] = self.refs.get(tok, 0) + 1
        self.edits = []                                  # (first_line_idx, last_line_idx, new_text, note)

    def m(self, k):  return self.ins[k].mn if k < len(self.ins) else None
    def o(self, k):  return self.ins[k].opnd if k < len(self.ins) else None

    def safe_after(self, k, hops=0):
        """Can the instruction at ins[k] observe A / the flags? -> (safe, why)"""
        if k >= len(self.ins): return True, "end"
        mn, op = self.m(k), self.o(k)
        if mn in SAFE_NEXT: return True, mn
        if mn == "JSR":
            name = op.split(",")[0].strip()
            if name in self.allow_jsr: return True, "JSR " + name
            return False, "JSR %s (not in --allow)" % name
        if mn == "JMP":
            tgt = op.strip()
            if hops < 1 and tgt in self.labels:
                s, why = self.safe_after(self.labels[tgt], hops + 1)
                return s, "JMP %s -> %s" % (tgt, why)
            return False, "JMP " + tgt
        return False, mn + " " + op

    def first_line(self, k):  return self.ins[k]
    def label_of_first(self, k):
        # a label on the first replaced line is kept in front of the new instruction
        return self.ins[k].label

    def span_has_foreign_label(self, k0, k1):
        """A label on any instruction strictly inside the span (not the first) would
        make the middle of the sequence a jump target: never rewrite those."""
        for k in range(k0 + 1, k1 + 1):
            if self.ins[k].label: return True
        return False

    def emit(self, k0, k1, new, note):
        lab = self.label_of_first(k0)
        pre = ("%-8s" % (lab + ":")) if lab else "        "
        text = pre + new + "                ; <- tierA: " + note
        self.edits.append((self.ins[k0].idx, self.ins[k1].idx, text, note))

    def try_at(self, k):
        m, o = self.m, self.o
        # ---- LDA x / STA y / LDA x+1 / STA y+1  ->  MOVW y,x
        if m(k) == "LDA" and m(k+1) == "STA" and m(k+2) == "LDA" and m(k+3) == "STA":
            x, y = o(k), o(k+1)
            if not x.startswith(("#", "(")) and not y.startswith("(") and o(k+2) == x + "+1" and o(k+3) == y + "+1":
                return k+3, "MOVW %s,%s" % (y, x), "word move"
            if x.startswith("#") and o(k+2).startswith("#") and o(k+3) == y + "+1" and not y.startswith("("):
                lo, hi = x[1:].strip(), o(k+2)[1:].strip()
                if is_lit(lo) and is_lit(hi):
                    return k+3, "LDW %s,#%d" % (y, (lit(hi) << 8) | lit(lo)), "word constant"
                if lo.startswith("<") and hi.startswith(">") and lo[1:] == hi[1:]:
                    return k+3, "LDW %s,#%s" % (y, lo[1:].strip()), "address constant"
        # ---- LDA #0 / STA y / STA y+1  ->  LDW y,#0
        if m(k) == "LDA" and o(k) in ("#0", "#$0", "#$00") and m(k+1) == "STA" and m(k+2) == "STA" \
                and o(k+2) == o(k+1) + "+1" and not o(k+1).startswith("("):
            return k+2, "LDW %s,#0" % o(k+1), "zero word"
        # ---- LDA x / TAPnL / LDA x+1 / TAPnH  ->  LPWn x ;  LDA #<s / TAPnL / LDA #>s / TAPnH -> LDPn #s
        if m(k) == "LDA" and m(k+1) in ("TAP1L", "TAP2L", "TAP3L") and m(k+2) == "LDA" and m(k+3) == m(k+1)[:4] + "H":
            n = m(k+1)[3]; x = o(k)
            if not x.startswith(("#", "(")) and o(k+2) == x + "+1" and n in "12":
                return k+3, "LPW%s %s" % (n, x), "pointer load"
            if x.startswith("#<") and o(k+2).startswith("#>") and x[2:].strip() == o(k+2)[2:].strip():
                return k+3, "LDP%s #%s" % (n, x[2:].strip()), "pointer constant"
        # ---- 16-bit increment / add-constant / decrement chains
        x = o(k) if m(k) == "LDA" else None
        if x and not x.startswith(("#", "(")):
            tail = None
            if m(k+1) == "INC" and m(k+2) == "STA" and o(k+2) == x and m(k+3) == "JNZ":
                fix, lab, op_new = k+4, o(k+3), "INCW %s" % x
            elif m(k+1) == "LDB" and m(k+2) == "ADD" and m(k+3) == "STA" and o(k+3) == x and m(k+4) == "JNC" \
                    and o(k+1).startswith("#") and is_lit(o(k+1)[1:]):
                kk = lit(o(k+1)[1:]); fix, lab = k+5, o(k+4)
                op_new = "INCW %s" % x if kk == 1 else "ADDW %s,#%d" % (x, kk)
            elif m(k+1) == "LDB" and o(k+1) == "#1" and m(k+2) == "SUB" and m(k+3) == "STA" and o(k+3) == x and m(k+4) == "JC":
                fix, lab, op_new = k+5, o(k+4), "DECW %s" % x
            else:
                fix = None
            if fix is not None and m(fix) == "LDA" and o(fix) == x + "+1" \
                    and m(fix+1) == ("DEC" if op_new.startswith("DECW") else "INC") \
                    and m(fix+2) == "STA" and o(fix+2) == x + "+1":
                nxt = fix + 3
                # tail A: the skip label is defined right after the chain, referenced once
                if nxt < len(self.ins) and self.ins[nxt].label == lab and self.refs.get(lab, 0) == 1:
                    # the label line carries the following instruction: keep that
                    # instruction, drop the label (it has no other reference)
                    return ("chain", fix+2, op_new, "16-bit %s chain, skip label %s dropped" % (op_new.split()[0], lab), nxt)
                # tail B: the chain ends in `JMP lab` (a loop head): keep the JMP
                if m(nxt) == "JMP" and o(nxt) == lab:
                    return fix+2, op_new, "16-bit %s chain before JMP %s" % (op_new.split()[0], lab)
        return None

    def run(self):
        k = 0
        while k < len(self.ins):
            r = self.try_at(k)
            if r is None:
                k += 1; continue
            if r[0] == "chain":
                _, k1, new, note, labk = r
                nxt_k = labk
            else:
                k1, new, note = r; nxt_k = k1 + 1
            if self.span_has_foreign_label(k, k1):
                self.report(k, k1, new, "SKIP: label inside the sequence"); k += 1; continue
            safe, why = self.safe_after(nxt_k)
            if not safe:
                self.report(k, k1, new, "SKIP: next = " + why); k += 1; continue
            if r[0] == "chain":
                # drop the label from the line that carries it (keep its instruction)
                l = self.ins[labk]
                self.edits.append((l.idx, l.idx, "        " + l.text.split(":", 1)[1].lstrip() if ":" in l.text.split(";")[0] else l.text, "label dropped"))
            self.emit(k, k1, new, note + " (next: %s)" % why)
            self.report(k, k1, new, "OK   next = " + why)
            k = nxt_k

    def report(self, k, k1, new, verdict):
        print("%5d-%-5d %-28s %s" % (self.ins[k].idx + 1, self.ins[k1].idx + 1, new, verdict))

    def apply(self, path):
        text = [l.text for l in self.L]
        for a, b, new, note in sorted(self.edits, key=lambda e: -e[0]):
            text[a:b + 1] = [new]
        open(path, "w").write("\n".join(text))


def main():
    a = sys.argv[1:]
    if not a: sys.exit(__doc__)
    path = a[0]; apply = "--apply" in a
    allow = set()
    if "--allow" in a:
        for spec in a[a.index("--allow") + 1].split(","):
            allow.add(spec.split(":")[-1])
    rw = Rewriter(load(path), allow)
    rw.run()
    n_ok = len([e for e in rw.edits if e[3] != "label dropped"])
    print("%s: %d rewrites%s" % (path, n_ok, " applied" if apply else " (dry run; --apply to write)"))
    if apply and rw.edits: rw.apply(path)


if __name__ == "__main__":
    main()
