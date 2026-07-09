# commands-asm — hand-coded assembler versions of the /bin commands

An experiment (branch `commands-asm`): rewrite the C `/bin` commands
(`os/commands/*.c`, compiled by `p8cc`) as **hand-written P8X assembler**, to
measure how much smaller carefully hand-coded asm is than the current `p8cc`
codegen. This is the concrete data behind the backlog's "ASM vs C commands"
question and the p8cc codegen-size concern (grep/sed/vi live at the 64 K TPA
ceiling because of code size).

Each `NAME.asm` here is a drop-in replacement for `/bin/name.bin`: same entry
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
| touch   | 3420 |      524 | 6.5×  |
| pwd     |  939 |      174 | 5.4×  |
| more    |13542 |     3418 | 4.0×  |
| sed     |21491 |     5430 | 4.0×  |
| mv      |15526 |     4089 | 3.8×  |
| head    |13358 |     3536 | 3.8×  |
| wc      |13739 |     3655 | 3.8×  |
| uniq    |14589 |     4026 | 3.6×  |
| cat     |11906 |     3428 | 3.5×  |
| dir     |10195 |     4021 | 2.5×  |
| tree    | 3440 |     1358 | 2.5×  |
| vi      |32871 |    13460 | 2.4×  |
| grep    |26959 |    12507 | 2.2×  |
| cp      |18010 |     9032 | 2.0×  |
| tail    |25624 |    14125 | 1.8×  |
| sort    |25844 |    14117 | 1.8×  |
| find    | 9415 |     6413 | 1.5×  |
| diff    |23080 |    16858 | 1.4×  |
| **TOTAL** |**283948** | **120171** | **2.4×** |

(Regenerate with `compare.sh`; the C sizes include the `//#use` shared libs
spliced by `clib.py`, and each hand-asm binary that declares `;#use` likewise
counts its include, so the comparison is apples-to-apples.)

## Takeaways

All 18 `/bin` commands are ported and verified **byte-identical** to their p8cc
twin by `verify.sh` (diff of emulator transcripts) — so the sizes compare
equivalent behavior, not a cut-down reimplementation. The overall win is **2.4×**
(284 KB → 120 KB), but it splits cleanly by what a command's binary is *made of*:

- **Code-dominated → 3.5–5.8×** (pwd, mv, more, sed, head, wc, uniq, cat). This
  is the real result: p8cc's stack-machine codegen — every subexpression pushed
  and popped through the `__csp` software stack — is pure overhead that
  straight-line register asm erases. `sed` (a full regex substitutor) at 4.0×
  and `more`/`head`/`wc` near 4× are the headline numbers.
- **Big-fixed-data → 1.4–2.0×** (diff, tail, sort, cp, find). These carry large
  buffers that are *identical bytes in both builds* — diff's two 7.7 KB line
  arrays, tail's 10 KB ring, sort's 10 KB, cp/find's per-level recursion arrays.
  The data dominates the binary, so the code shrink barely moves the total. The
  code portion still shrank ~3–5×; the ratio just measures data too.
- **Middle (2.2–2.5×)**: dir/tree (small C already, hand asm pays for manual
  16-bit index math), and grep/vi (large programs with a mix of code and buffers).

Shared hand-asm includes mirror the C `//#use` model (spliced by `mkasm.sh`):
`lib_stdin.inc` (open/read/glob engine), `lib_glob.inc` (gmatch + de[]),
`lib_regex.inc` (the recursive `. * + ? ^ $` matcher for grep/sed),
`lib_globx.inc` (glob expansion for cp/mv wildcards, on top of `lib_glob.inc`).

Two structural techniques recur, forced by the ISA (P3 is the hardware stack
pointer, so only P1/P2 are general-purpose and there are no cheap software-stack
frames): recursion is done with **depth-indexed arrays + a global `w_depth`**
(tree, dir, find, cp, grep), and the genuinely recursive regex/glob matchers save
their pointer args on the **hardware stack** across non-tail calls. The CPU has
no divide, so decimal output uses a `divmod10` subtraction routine.
