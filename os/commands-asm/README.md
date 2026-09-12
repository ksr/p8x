# commands-asm — hand-coded assembler versions of the /bin commands

An experiment (branch `commands-asm`): rewrite the C `/bin` commands
(`os/commands/*.c`, compiled by `p8cc`) as **hand-written P8X assembler**, to
measure how much smaller carefully hand-coded asm is than the current `p8cc`
codegen. This is the concrete data behind the backlog's "ASM vs C commands"
question and the p8cc codegen-size concern (grep/sed/vi live at the 64 K TPA
ceiling because of code size).

Each `NAME.asm` here is a drop-in replacement for `/bin/name.bin`: same entry
(`$6A00`), same argument ABI (`P2` = arg-tail pointer), same OS/BIOS calls, so it
must produce **byte-identical behavior** to the C version — verified in the
emulator, not just assumed.

## The ABI a command relies on

| call | addr | in | out |
|------|------|----|-----|
| entry | `$6A00` | `P2` = ptr to NUL-terminated arg tail | `RTS` to OS |
| SYS_GETCWD | `$2003` | `P1` = dest buf | CWD path (incl. NUL) copied |
| SYS_PUTC | `$2009` | `A` = char | — |
| SYS_PUTS | `$200F` | `P1` = string | prints string, no newline |
| SYS_GETC | `$200C` | — | `A` = char, or EOF |
| FRESOLVE | `$0133` | `P1` = path | sets DIRLBA/FNAME |
| FOPEN | `$0124` | `P1` = 512-byte buf | `C`=1 if not found |
| FGETB | `$0127` | — | `A` = byte, `C`=1 at EOF |

`puts(s)` in the C world = `SYS_PUTS(s)` then `SYS_PUTC(10)`.

## Measuring

```
sh os/commands-asm/compare.sh
```

builds every `os/commands/NAME.c` with `p8cc` and every `os/commands-asm/NAME.asm`
by hand — both through the same `p8xasm.py --base 0x6A00` — and prints a
size table with the ratio. Ported commands only in the TOTAL.

## Scoreboard (fill-binary bytes)

Regenerated 2026-09-12, after the Tier A ISA work: **both** columns moved. The
compiled column shrank by more than half (frames on P3, word instructions,
`CMPW` conditions, relaxed branches), and the hand-asm column shrank ~4.5%
(`tools/tierA_rewrite.py` replaced its byte-wise word moves, pointer loads
and carry chains with single instructions).

| command | p8cc | hand-asm | ratio |
|---------|-----:|---------:|------:|
| touch   |  877 |      431 | 2.0×  |
| pwd     |  282 |      164 | 1.7×  |
| wc      | 5715 |     3580 | 1.6×  |
| more    | 4760 |     3169 | 1.5×  |
| mv      | 5678 |     3786 | 1.5×  |
| uniq    | 5475 |     3746 | 1.5×  |
| cat     | 4498 |     3265 | 1.4×  |
| head    | 4711 |     3261 | 1.4×  |
| sed     | 7031 |     4953 | 1.4×  |
| dir     | 7339 |     6352 | 1.2×  |
| vi      |15837 |    13358 | 1.2×  |
| diff    |17516 |    16608 | 1.1×  |
| sort    |15619 |    13961 | 1.1×  |
| tail    |15450 |    13843 | 1.1×  |
| grep    |10953 |    11932 | 0.9×  |
| cp      | 6556 |     8728 | 0.8×  |
| tree    | 1031 |     1318 | 0.8×  |
| find    | 3001 |     6172 | 0.5×  |
| **TOTAL** |**132329** | **118627** | **1.1×** |

(Regenerate with `compare.sh`; the C sizes include the `//#use` shared libs
spliced by `clib.py`, and each hand-asm binary that declares `;#use` likewise
counts its include, so the comparison is apples-to-apples. The 2026-08 table
this replaces read 2.4× overall, 291,442 vs 122,770 bytes.)

## Takeaways

All `/bin` twins are verified **behaviourally identical** to their C version by
`verify.sh` (diff of emulator transcripts), so the sizes compare equivalent
behavior. The 2026-08 finding -- hand asm 2.4× smaller, up to 5.8× on
code-dominated commands -- was a measurement of the OLD compiler: its software
C-stack, byte-by-byte word moves and helper calls for every operator. With the
Tier A ISA and the compiler emitting it, that overhead is gone and the gap
closed to **1.1× overall**:

- **Code-dominated commands (1.4–2.0×)**: hand asm still wins where a routine
  is a tight byte loop the compiler cannot see through (`wc`, `more`, `uniq`,
  `sed`), but the margin is now bytes, not multiples.
- **Data-dominated and recursive commands (0.5–1.1×)**: the compiler now
  WINS. `find` is half the size of its twin, `cp` and `tree` 0.8×, `grep` 0.9×:
  the twins pay for depth-indexed recursion arrays and manual 16-bit index
  math, while the compiled version keeps its locals in P3 frames and lets
  `LDW (P3+d)` do the indexing. `diff`/`sort`/`tail` are large buffers in both
  builds, so they sit at 1.1×.

So the reason this directory exists -- size -- has largely evaporated. What the
twins still offer is speed in hand-tuned inner loops and a second,
independently written implementation that the differential tests check the
compiler against. Whether to keep porting new commands to asm is now a judgment
per command, not a rule; see the BACKLOG discussion.

Shared hand-asm includes mirror the C `//#use` model (spliced by `mkasm.sh`):
`lib_stdin.inc` (open/read/glob engine), `lib_glob.inc` (gmatch + de[]),
`lib_regex.inc` (the recursive `. * + ? ^ $` matcher for grep/sed),
`lib_globx.inc` (glob expansion for cp/mv wildcards, on top of `lib_glob.inc`),
`lib_gfx.inc` (equates for the GL/PGC port — `GLDATA = $FF50`, `GLSTAT =
$FF51`, … — the asm twin of the C `//#use gfx` library's address book),
and `lib_abi.inc` (equates naming the BIOS jump table + OS syscalls — `FOPEN =
$0124`, `SYS_GETCWD = $2003`, … — so a twin `;#use abi` and does `JSR FOPEN`, the
asm counterpart of the C side's `//#use abi` / `os/commands/lib_abi.c` #defines).

Two structural techniques recur, forced by the ISA (P3 is the hardware stack
pointer, so only P1/P2 are general-purpose and there are no cheap software-stack
frames): recursion is done with **depth-indexed arrays + a global `w_depth`**
(tree, dir, find, cp, grep), and the genuinely recursive regex/glob matchers save
their pointer args on the **hardware stack** across non-tail calls. The CPU has
no divide, so decimal output uses a `divmod10` subtraction routine.
