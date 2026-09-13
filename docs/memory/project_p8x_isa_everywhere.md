---
name: p8x-isa-everywhere
description: the 2026-09-12 program that put the whole toolchain and ALL shipped code on the Tier A ISA -- DONE the same day (p8cc.c codegen rewrite; on-board asm/cc; twins+libs; OS+WM; monitor; editor; BASIC via tools/tierA_rewrite.py); numbers, design choices, gotchas, and the hardware follow-ups (reburn program + control-store EPROMs, re-clone SD)
metadata:
  type: project
---

**User request (2026-09-12):** "be sure all Mac hosted tools emit latest ISA;
look at all C and asm libraries to rewrite with latest tools; compile all C
source with updated tools; update all asm code taking advantage of latest ISA."
Tracked as the `[~]` item at the top of BACKLOG NEXT.

**Stage 1 DONE — `compiler/p8cc.c` codegen rewrite.** Same Tier A model as
p8cc.py (P3 frames, ADDW/SUBW/ANDW/ORW/XORW on __ax, CMPW + one branch, JMP.A,
`.relax`, runtime __mul/__divmod/__shl/__shr/branch-free __cmp16). It is
SINGLE-PASS, so: leaf operands are PENDING (`pk` 1 const / 2 variable / 3 string
/ 4 array address; `flush_val`, `flush_addr`, `leaf_t`, `byte_a`, `push_val`),
`peek_leaf(level)` looks one token ahead to avoid spilling the left operand,
conditions run in a jump-if-false mode (`cmode/clabel/cdone`; `cond_has_or`
pre-scan falls back to a value test; parens/call args/index/assignment rhs reset
cmode), `binexpr(level)` is ONE table-driven function for all 8 binary levels,
and the LAST argument travels in __ax (args parsed left to right; callee slot
P3+1 via `body_uses`; params i<n-1 at L+3+2(n-2-i)). Locals get slots from a
pre-scan (`count_locals` -> `pre_*` table, scalars first, first declaration
wins); far path (`far_la`/`far_p1`, `__la`) for displacements > 255. Not ported:
dead-function elimination, most narrow paths. Gaps fixed on the way (they broke
disasm/cube/house/finder before too): brace + string global initializers
(`gil_*` pool, `intern_str`), plain `#define`, function return types
(`addfunc`/`functype`). Results: all 45 /bin commands compile, 342,372 B
(p8cc.py 284,835); c_selfhost PASS; the compiler test program prints all 13
markers under both compilers.

**Gotchas met:** a `char op[3]` buffer got "ORW"/"XORW" copied into it and
smashed the neighbouring locals -- symptoms were wild parse errors ("bad
factor", "expected ;") far from the cause; keep mnemonic scratch buffers >= 8.
`z16` (Z valid after an immediate word op) is cleared inside `emitstr` so any
emitted text invalidates it. The self-compile of p8cc.c cannot be ASSEMBLED
(host-sized tables > 64 KB), only compiled -- as before. Test scripts must be
run FROM `emulator/test` (a background batch launched after a `cd` elsewhere
silently produced no results).

**On-target toolchain DONE (2026-09-12, user asked to start it):** step 0 of
the archived os-rewrite cherry-picked (389eb76 on graphics-card; conflict = the
deleted plan doc, resolved by `git rm`), then `apps/p8xcc.asm` ported at the
TEMPLATE level, keeping its static-slot model: LDW #n literals, ADDW/SUBW/ANDW/
ORW/XORW __ax,__t0 (MSUB = `SUBW __t0,__ax ; MOVW __ax,__t0`), ADDW #k offsets,
INCW/DECW slots, CMPW #0 tests, `CMPW __t0,__ax` for < >= and the SWAPPED
`CMPW __ax,__t0` for > <= (single branch; == != keep JSR __cmp for a 16-bit Z),
args on P3 (PHW; callee `LDW __V+2s,(P3+3+2(n-1-i))`; caller ADDP3), slot saves
BEFORE the args and DISCARDED (ADDP3) when SAWADDRG, p8cc startup. Native
output uses absolute branches only, so the old flag/A idioms stay valid there.
Test program 5,546 -> 2,458 B. Gotcha: gen_p8xopc.py imports genucode via
HERE/../microcode -- run an archived copy with PYTHONPATH=<repo>/microcode.

**Tool bodies + cc output (2026-09-12):** `tools/tierA_rewrite.py` written
(patterns: word move, word/address constant, zero word, LPWn/LDPn pointer
loads, INC/ADD #k/DEC carry chains with a dropped skip-label or a `JMP loop`
tail; safety = next executed instruction in SAFE_NEXT, JSR only via --allow,
JMP followed one hop; internal labels must be referenced once). p8xasm.asm 36
sites, p8xcc.asm 88 sites, tests green. p8xcc.asm output: condition mode
(GEXPR copies CONDF->CONDCUR and clears it; GREL branches via EMITCF when the
relop is followed by ')' or ';'; statements pre-allocate the false label) and
statement-level ++/-- as INCW/DECW. Test program on the board 5,546 -> 2,041 B;
same subset program p8cc.py 1,066 / p8cc.c 1,107 / on-board 2,146 B. Remaining
idioms in both tools are LDA/LDB #k/CMP byte compares -- no better form exists.
The three compilers will never emit identical code (P3 frames + AST
optimisations vs static slots vs single-pass): equivalence is BEHAVIOURAL,
checked by the differential tests.

**Twins + asm libs DONE (2026-09-12):** apply script per file with allow-lists
(scratchpad apply_twins.sh; the allow-lists are in BACKLOG's item); 662 sites /
32 files; /bin 148,744 -> 142,115 B (-4.5%). Tests: os_asm_use, cmdbuild
(asm-match), os_cmp, os_awk, os_examine, c_image (twin identical), c_vi_relpath,
os_mk + full suite. The user's order after this: OS + WM kernel, then monitor.
C libraries need NO change (spliced source, recompiled with the new tools).

**OS + WM kernel DONE (2026-09-12):** 24 + 109 sites; OS 14,681 -> 13,798 B;
os_asm + wm_* + desktop tests green. Monitor DONE (18 sites, ROM used 5,297 -> 5,184 B, `make rom` regenerated).
Still to do in stage 4: apps/p8xedit.asm (1 site) and basic/p8xbasic.asm (93 + 38
with allow ADD16,CMP16,DIV16,HEXDIG,MUL16,PRDEC,RANDOM,SAPP,SHL16,SKIPSP,SMOVE,
SUB16,SARG,SCPYLIT). The disk build assembles both at test time, so apply them
only between suite runs. p8xbasic.asm needs -D BASORG/BASRAM/PBUF/MONITOR to
assemble standalone (see os/run.sh line ~215). **p8cc.c fit check:** code+small data 35,468 B vs TPA 36,352 B; the
266 KB of host-sized tables are the blocker (stream the source, cut tables,
multi-pass) -- see BACKLOG.

**Editor + BASIC DONE (2026-09-12):** p8xedit 1 site (1,607 -> 1,602 B), BASIC
128 sites (11,887 -> 11,151 B; allow list as planned). PROGRAM COMPLETE -- the
item moved to BACKLOG-DONE; the follow-up is the optional manual hot-loop pass.
HARDWARE: the TTL machine needs its program EPROM and all four control-store
EPROMs reburned (rom/) and the SD card re-cloned; the FPGA rebuilds from the
same files.

**(historical) Next stages:** (2) C libs `os/commands/lib_*.c` + `compiler/p8lib.c` and asm
libs `os/commands-asm/*.inc` review; (3) rebuild /binc + disk via run.sh, full
suite; (4) hand-asm rewrite (the native assembler now has the two-operand shapes; no
`.relax` natively, so hand asm uses absolute branches only) -- incl. the bodies
of p8xcc.asm / p8xasm.asm themselves. Related:
[[p8x-tier-a-isa]], [[p8x-cycle-bench]], [[p8cc-runtime-order-gate]].
