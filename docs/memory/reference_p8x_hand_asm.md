---
name: reference_p8x_hand_asm
description: P8X hand-assembly gotchas for writing /BIN commands in raw asm (commands-asm experiment)
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

Writing P8X /BIN commands in hand assembler (the `commands-asm` experiment under
[[project_p8x]]). Hard-won facts:

- **P3 is the hardware stack pointer** (microcode `psel=3` = SP; every JSR/RTS
  and BIOS/OS call pushes/pops it). P0 is the PC. Only **P1 and P2 are
  general-purpose** pointer registers. Never load P3 as a data cursor — it
  corrupts the stack and the next RTS resets the machine to the monitor banner.
- **OS syscalls / BIOS calls clobber P1 and P2** — reload any pointer cursor
  from a memory word after a `JSR $40xx`/`$01xx`. (SYS_GETCWD clobbers P2.)
- `CMP` = SUB with `dld=none`: sets flags, **preserves A**. So `LDA (P2); LDB
  #x; CMP; JZ ...` can chain multiple compares without reloading A.
- `bios(fn, p1arg, aarg)` ABI: p1arg→P1 (via TAP1L/TAP1H), aarg→A, then `JSR fn`;
  returns A (low) + carry (test with JC/JNC directly instead of the C `&256`).
- Command ABI: entry `$7A00`, `P2` = arg-tail pointer. SYS_GETCWD $4003,
  SYS_PUTC $4009, SYS_PUTS $400F (no newline; `puts` = SYS_PUTS then PUTC(10)).
- The **emulator loads microcode `u?.bin` from the CWD** — run it from a dir
  that has them, or the CPU executes zeroed microcode and resets.
- Hand asm is dramatically smaller than p8cc: pwd 174 vs 939 B (5.4x), mv 781 vs
  4585 B (~5.9x). See os/commands-asm/compare.sh + verify.sh.
