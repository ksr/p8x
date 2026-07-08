# commands-asm — hand-coded assembler versions of the /BIN commands

An experiment (branch `commands-asm`): rewrite the C `/BIN` commands
(`os/commands/*.c`, compiled by `p8cc`) as **hand-written P8X assembler**, to
measure how much smaller carefully hand-coded asm is than the current `p8cc`
codegen. This is the concrete data behind the backlog's "ASM vs C commands"
question and the p8cc codegen-size concern (grep/sed/vi live at the 64 K TPA
ceiling because of code size).

Each `NAME.asm` here is a drop-in replacement for `/BIN/NAME.BIN`: same entry
(`$7A00`), same argument ABI (`P2` = arg-tail pointer), same OS/BIOS calls, so it
must produce **byte-identical behavior** to the C version — verified in the
emulator, not just assumed.

## The ABI a command relies on

| call | addr | in | out |
|------|------|----|-----|
| entry | `$7A00` | `P2` = ptr to NUL-terminated arg tail | `RTS` to OS |
| SYS_GETCWD | `$4003` | `P1` = dest buf | CWD path (incl. NUL) copied |
| SYS_PUTC | `$4009` | `A` = char | — |
| SYS_PUTS | `$400F` | `P1` = string | prints string, no newline |
| SYS_GETC | `$400C` | — | `A` = char, or EOF |
| FRESOLVE | `$0133` | `P1` = path | sets DIRLBA/FNAME |
| FOPEN | `$0124` | `P1` = 512-byte buf | `C`=1 if not found |
| FGETB | `$0127` | — | `A` = byte, `C`=1 at EOF |

`puts(s)` in the C world = `SYS_PUTS(s)` then `SYS_PUTC(10)`.

## Measuring

```
sh os/commands-asm/compare.sh
```

builds every `os/commands/NAME.c` with `p8cc` and every `os/commands-asm/NAME.asm`
by hand — both through the same `p8xasm.py --base 0x7A00` — and prints a
size table with the ratio. Ported commands only in the TOTAL.

## Scoreboard (fill-binary bytes)

| command | p8cc | hand-asm | ratio |
|---------|-----:|---------:|------:|
| pwd     |  939 |      174 | 5.4×  |
| mv      | 4585 |      789 | 5.8×  |
| tree    | 3440 |     1358 | 2.5×  |
| dir     |10195 |     4021 | 2.5×  |
| wc      |13739 |     3655 | 3.8×  |
| head    |13358 |     3536 | 3.8×  |
| tail    |25624 |    14125 | 1.8×  |
| uniq    |14589 |     4026 | 3.6×  |
| cat     |11906 |     3428 | 3.5×  |
| **TOTAL** |**98375** | **35112** | **2.8×** |

(Regenerate with `compare.sh`; the C sizes include the `//#use` shared libs
spliced by `clib.py`, and each hand-asm binary that declares `;#use stdin`
likewise counts `lib_stdin.inc`, so the comparison is apples-to-apples.)

## Takeaways

- Hand asm is **2–6× smaller**, but the win depends on the command's shape:
  - **Code-dominated** (pwd, mv, wc, head, uniq, cat): **3.5–5.8×**. p8cc's
    stack-machine codegen — every expression pushed/popped through `__csp` —
    is where the bloat lives; straight-line register asm collapses it.
  - **Buffer/data-dominated** (tail): **1.8×**. tail's 10 KB line ring is
    identical fixed data in both, so it dilutes the code-size win.
  - **Small + pointer-arithmetic-heavy** (tree, dir): **2.5×**. These are
    already small in C, and hand asm pays for manual 16-bit index math
    (depth-indexed arrays, `divmod10`) that the compiler emits compactly.
- The heavy commands (`grep`, `sed`, `vi`, `sort`, `diff`, `find`, `more`,
  `cp`) were out of scope for this pass — `grep`/`sed` need the regex matcher
  hand-assembled and `vi` is a screen editor. The representative set above is
  enough to characterize the ratio.
- Every ported command is verified **byte-identical** to its p8cc twin by
  `verify.sh` (diff of emulator transcripts), so the sizes compare equivalent
  behavior, not a cut-down reimplementation.
