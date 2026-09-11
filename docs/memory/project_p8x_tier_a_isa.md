---
name: p8x-tier-a-isa
description: Tier A C-compiler ISA (24 pure-microcode opcodes) implemented on the emulator 2026-09-11; what is done, the contracts, the consumers that must follow, and what is still open (p8cc emitters, self-hosting, TTL reburn)
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
**Still open:** the frame model (locals/args still on the software C-stack —
SP-relative on P3 vs a Tier B P4 is the user's open question; a P3 frame needs
args little-endian on the stack, i.e. PHW/PLW byte order flipped);
self-hosting compilers (`p8cc.c`, `p8xcc.asm`); native assembler parsing of the
compiler-only shapes; control-store EPROM reburn for the TTL machine (FPGA and
emulator need nothing). Related: [[p8cc-runtime-order-gate]], [[p8cc-int-is-unsigned]].
