---
name: p8x-cycle-bench
description: how to measure P8X speed in cycles (p8xemu -L LED stamps bracketing poke(65282,n)); the 2026-09-11/12 control-flow microstep results; taken relative branches now clobber A+flags (8 steps) and the compiler emits JMP.A for always-taken jumps; the test_isa $0808 vector layout gotcha
metadata:
  type: reference
---

**Measuring speed.** `p8xemu -L` prints `[LED $FF02 @<cycles>] $nn` to stderr
on every LED-port write, so a program brackets a span with `poke(65282, 1)` …
`poke(65282, 2)` and the cycle difference is the span's cost (cycles = microsteps,
1 per step incl. fetch). Run the compiled program from a disk image under the OS
(`printf 'B\rrun X.bin\r' | p8xemu -L -l N -c img eeprom.bin`). The emulator
loads `u0-u3.bin` from the CWD, so an A/B against another microcode is just a
different directory with the other images. `test_isa` cycle count (HALT line) is
a branch-heavy micro-benchmark on its own.

**Control-flow microstep audit (2026-09-11):** `JMP a` 3 steps, absolute `Jcc`
3 taken / 2 not taken, `JSR a` 9, `RTS` 5, `RTI` 7, `PLW` 9, `PHW` 8,
`PHW (Pn+d)` 9. Tricks: a pointer loads FROM THE BYTE IT ADDRESSES in one step
(`doe=MEM,dld=PTRH,psel=0`), and `SP++ ; read` merges into a post-increment read
(the first SP++ of a pop cannot merge). `JSR (P1)` and the relative branches
have no slack. Result: test_isa −5%, OS boot −5.3%, compiled workload −0.4%.

**Finding + decision (2026-09-12):** in compiled code the cost was the RELATIVE
branches — a taken `Jcc rel8` was 14 steps (push A, save FLAGS, sign-extend,
add, carry-plane, restore) vs 3 absolute. DONE: the taken path now CLOBBERS A
and the flags (8 steps; B kept; not-taken 2 steps, untouched) — an ISA contract
change — and the compiler emits every unconditional jump as `JMP.A` (forced
absolute, new assembler suffix); its four idioms that read A/flags after a taken
branch are branch-free (`LDA #0 / ROL` = carry as 0/1; `ROL / XOR #1` = borrow;
`__cmp16` = SUB/SUB/OR). Workload 783,637 → 735,142 cycles (−6.2%); /bin total
even shrank (284,835). RULE: never read A or the flags after a taken relaxed
branch; hand asm using `.R` must respect it.

**Gotcha:** `emulator/test/test_isa.asm` must keep its body ABOVE the IRQ
vector `$0808` (the handler sits there; `JMP start` at the top hops over it).
When the body grew past it (E-series, 2026-09-11) execution ran into the handler
and an RTI on garbage — and the test still "passed" by luck (A=00 at the end).
Check `[HALT after N cycles]` in `tisa.out`, not just A=00. Related:
[[p8x-tier-a-isa]].
