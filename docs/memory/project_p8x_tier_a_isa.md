---
name: p8x-tier-a-isa
description: Tier A C-compiler ISA (39 pure-microcode opcodes, 143 total) implemented on the emulator 2026-09-11 with all p8cc emitter stages (-54.5% across /bin); the contracts (16-bit Z on immediate forms only), the consumers that must follow any new opcode, and what is still open (self-hosting, TTL reburn; shared runtime parked)
metadata:
  type: project
---

**Tier A of docs/p8x-isa-c-extensions.md is implemented on the emulator
(2026-09-11).** 24 opcodes, 88 → 112 defined, all pure microcode in
`microcode/genucode.py` (`alu_mid`, `ALU["ZERO"]`/`["SBB"]`, `_ld_pt2`,
`_pt_disp`): `LDPn #imm16` $38–$3A, `ADDP3`/`SUBP3 #` $3C/$3D, `LDA`/`STA (Pn+d)`
$88–$8A/$8C–$8E, `LDW a,(Pn+d)`/`STW (Pn+d),a` $90–$92/$94–$96, `LDW a,#imm8`/`#imm16`
$98/$99, `ADDW`/`SUBW`/`CMPW a,b` $9A–$9C, `INCW`/`DECW a` $9E/$9F.

**Carry chain = condition planes:** ALU step latches C (ldf) → the NEXT step
carries `fcond="C"` → the step after is a (C=0, C=1) plane pair. The one-step lag
is real hardware timing (flag reg → mux → ROM address); never put fcond on the
ALU step itself. `op()` now asserts ≤15 steps and no duplicate opcode.

**Contracts (on the ISA card):** the memory-to-memory forms clobber A and latch
flags (unlike LDA/STA abs); d8 unsigned; ADDW/SUBW/CMPW: C = 16-bit carry/no-borrow,
N^V signed order correct, **Z = high byte only** (equality needs its own test);
INCW/DECW/ADDP3/SUBP3 flags = low byte's. `PHW` still pushes lo-then-hi, so a
PHW'd word sits BIG-endian on the stack — `LDW (P3+d)` cannot read pushed args
without either a byte swap or flipping PHW/PLW order (only used as pairs: p8cc.py,
p8xcc.asm, 2 sites in commands-asm; nothing peeks the layout).

**Consumers that changed with it (all must follow any future opcode):** host
assembler (`COMP_BYTES`, `split_top`/`parse_one`/`resolve_shape`; imm8 vs imm16
chosen from the operand TEXT via `lit8` so both passes agree; byte stream =
address word first, then disp/imm — the assembler reorders `STW (Pn+d),a`);
`generators/gen_p8xopc.py` (`#w` = shape 9 for the native `DO_LDP` path, other
Tier A shapes in `HOST_ONLY`); `generators/gen_p8xdis.py` (shape codes 10–21) +
`disasm.c`/`disasm.asm` twins; `apps/p8xasm.asm` `DO_LDP` emits the real opcode;
`gen_isa_card.py`/`gen_progguide.py` SHN/BYTES/DESC/GROUPS (both regenerated);
`emulator/test/os_asm_test.sh` cover generator skips host-only shapes by table
membership; `c_disasm_test.sh` decodes one of each form; `test_isa.asm` C1–D1.

**p8cc emitters DONE (same day):** `LDW a,#` constants/addresses, in-place
`INCW`/`DECW`/`ADDW`/`SUBW` for statement-level `g = g ± k` on global words
(`gen_assign(want=False)` from gen_stmt), `CMPW g,__t` for orderings in
`gen_cond`, `LPW1` in bios()/puts(), `LDW __t,#k ; ADDW __ax,__t` for offsets /
`-e` / `~e` / arg drop. 532,728 → 428,320 (−19.6%; −31.7% vs 627,172 baseline).
**Frames on P3 DONE (same day):** `SUBP3 #L` / `ADDP3 #L`, locals at P3+1..L
(scalars first), ret addr at L+1, param i at L+3+2i; `self.sp` tracks the
compiler's own pushes and is added to every displacement (assert sp==0 at each
statement); far path (`__la`/`__lb`, `far_local`) for d>255; char slots keep a
zero high byte (`st_local(full=char_load(rhs))`, `zero_hi_local` for char
params); startup saves the caller's P3 in `__sp0`, relocates to CSTACKTOP-1
ONLY if P3 is above CSTACKTOP (normal launch from the 256-byte OS stack), and
`LPW3 __sp0` at exit. **Gotcha found the hard way:** a program launched while
the shell runs a script on a C program's stack (Finder → SYS_RUNSH → `run`)
inherits P3 ≈ $F7E3; relocating UP to $F7FF tramples the shell's pending return
addresses (reset to $0000 at exit). Two latent bugs surfaced because locals now
sit right below the return address: `p8lib.c loadfile` had `char de[17]` for an
18-byte SYS_DIRENTRY (fixed), and any local-array overrun now jumps to garbage
instead of silently scribbling RAM — trace with `p8xemu -t` and grep `DLD=7`
writes into the return slot / `P0=0000` fetches. Added opcodes: `ADDW/SUBW/CMPW a,#imm8` $A0-$A2 (T ZERO'd for the high
step), `LEAW a,(Pn+d)` $A4-$A6, `LPW3` $79 (119 opcodes total); **PHW flipped to
push hi-first** (word little-endian at P3+1). 627,172 → 374,672 = −40.3%
(finder 32,630 → 13,909).
**Relative branches DONE:** `Jcc r` $A8-$B0 (128 opcodes; `_rel_taken`: save
FLAGS→T2, A=d8 ldzn for the sign plane, DEC hi if negative, ADD lo, carry
plane, restore FLAGS). Assembler `.relax` (shrink-only iterative relaxation,
`relax_round`) + forced `.R` suffix; p8cc emits `.relax` first; hand sources
unchanged (byte-identical check vs the committed assembler). 369,209 total
(−41.1% overall). **Narrow values + peephole DONE:** `is_narrow`/`gen_byte_a`/
`byte_a_via_b` (+`__b` scratch) feed putchar, bios A operand, byte stores,
truth tests, 8-bit CMP compares; `peephole()` on adjacent lines. 341,137 total
(−45.6% overall). **Inline word ops + flag conditions + dead functions DONE
(2026-09-11, user approved microcode-only ISA additions, "no hardware changes
yet"):** `gen_wordop` (+ - & | ^ → ADDW/SUBW/ANDW/ORW/XORW on __ax; immediate
right side with pointer scale folded, ±1 → INCW/DECW, leaf → __t, `k - x`
parks x via MOVW), `gen_relcond` (C = (L >= R) normalisation, `k < x` → `x >=
k+1`, `CMPW g,#k` in place, `x == k` on the imm form's 16-bit Z, var==var keeps
__cmp16), `gen_value_z` (branch on ANDW's Z), `materialize()` for relops/!/&&/||
as values, `reachable()` drops uncalled functions. New opcodes $B1-$B3 (ADDW/
SUBW/CMPW a,#w) and $B4-$BC (ANDW/ORW/XORW a,b / a,# / a,#w) → 140 total.
**16-bit Z marker trick (immediate forms only, 14 steps):** after the low op,
`ZERO→A` + fcond Z, plane pair INC→T2 / ZERO→T2 (T2 = 0/1), high op latches,
fcond Z, plane pair (nothing / `doe=T2, ldzn`) — N := 0 there is correct since
the high result is 0. The a,b forms are at 14 steps already and keep Z =
high-byte-only; INCW/DECW flags = low byte's. 293,890 total (−53.1% overall,
finder 9,508); runtime now only __mul/__div/__mod/__divmod/__shl/__shr/__cmp16.
**PHW (Pn+d) + first arg in __ax DONE (same day):** `PHW (Pn+d)` $BD-$BF
(143 opcodes); `push_arg` (PHW (P3+d) / PHW label for scalars), arg 0 evaluated
LAST into __ax, callee `STW (P3+1),__ax` unless `names_used` says the param is
never read; param i>=1 at L+3+2(i-1). 285,072 total (-54.5%; finder 8,903).
Frame layout is in the p8cc docstring + compiler/README. Speed audit DONE 2026-09-11/12 (see
[[p8x-cycle-bench]]): JMP 3 / Jcc 3-2 / JSR 9 / RTS 5 steps; taken relative
branches CLOBBER A+flags (8 steps) and the compiler emits JMP.A for always-taken
jumps. OS-resident runtime PARKED by the user (BACKLOG item). Next: self-hosting -- DONE 2026-09-12 for emission (p8cc.c rewritten, p8xcc.asm
templates ported, native asm shapes cherry-picked as 389eb76); see
[[p8x-isa-everywhere]]. PARKED by the user, to revisit after those: scratch
rewrites of the monitor/OS around the new ISA, easy replacements first (they
were only re-assembled so far; idiom counts in BACKLOG — small wins, OS matters
because of its 16 KB ceiling). **Still open:**
self-hosting compilers (`p8cc.c`, `p8xcc.asm`); native assembler parsing of the
compiler-only shapes (DONE once on the dropped os-rewrite branch, commit 3e0e3c8,
kept as tag `archive/os-rewrite-2026-09-11` -- cherry-pick it, ASK first); control-store EPROM reburn for the TTL machine (FPGA and
emulator need nothing). Related: [[p8cc-runtime-order-gate]], [[p8cc-int-is-unsigned]].
