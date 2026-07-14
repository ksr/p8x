# P8X applications

Standalone **TPA programs** — assembled to load and execute at `$6A00` (the
transient program area), launched from P8X/OS with `RUN`. Each is built entirely
on the BIOS jump table (`$0100..`); none depend on OS internals, so they return
to the shell with a plain `RTS`.

Build one with the host assembler and place it on a disk:

```sh
python3 assembler/p8xasm.py apps/p8xedit.asm -o edit.bin --base 0x6A00
python3 tools/p8xfs.py put disk.img edit.bin --name /BIN/EDIT.BIN --load 0x6A00 --exec 0x6A00
```

`os/run.sh` already builds and installs these into a fresh demo disk under
`/BIN`, so a clean `./os/run.sh` boots an OS where `RUN EDIT.BIN NAME` works.

## EDIT — line-oriented text editor (`p8xedit.asm`)

```
RUN EDIT.BIN NAME.EXT
```

On entry the OS hands the program its argument tail in `P2` (the program-arg
ABI); EDIT copies it to `FNAME` and loads that file if it exists, else starts an
empty buffer. Text is held as LF-separated lines in `$C000..$F000` (12 KB).

| cmd | action |
|-----|--------|
| `L` | list every line with its 1-based number |
| `A` | append: type lines, end with a line containing only `.` |
| `I n` | insert before line `n` (n past the end appends); end with `.` |
| `D n` | delete line `n` |
| `W` | write the buffer back to the file (`FDELETE` then `FCREATE`) |
| `Q` | quit to the shell |
| `?` | command summary |

Notes / current limits: line numbers are 8-bit (≤255 lines); `W` rewrites the
whole file, orphaning the old data sectors until the next `PACK`; the editor
reads/writes the **root** directory (the BIOS FS layer is flat — path-aware
saves are a future item). Files use LF (`$0A`) line endings — the form the
on-target assembler (`ASM`) expects as input.

## ASM — native two-pass assembler (`p8xasm.asm`)

```
RUN ASM.BIN SRC.ASM OUT.BIN
```

Assembles `SRC.ASM` (read from the disk) and writes the binary `OUT.BIN`. The
output carries `load/exec = 0` from `FCREATE`, which the OS reads as the TPA
base `$6A00` — so a program written `.org $6A00` is **directly RUNnable** right
after assembling it. Pair with `EDIT` for a complete on-target edit → assemble →
run loop.

Accepted syntax is a subset of the host assembler, with identical encodings:

| form | example |
|------|---------|
| label | `loop:` |
| equate | `COUNT = 3` |
| instruction | `LDA #COUNT` · `STA $C000` · `LDA (P1)+` · `JSR done` |
| `LDPn` pseudo | `LDP1 #msg` → `LPL1 #<msg` ; `LPH1 #>msg` |
| directives | `.org .byte .word .ascii .asciiz .fill` |
| expressions | `$hex` · decimal · `'c'` · symbol, joined with `+`/`-`, optional `<`/`>` prefix |

A `;#use NAME` line (at column 0) appends the shared include `/lib/NAME.inc`
after the program body (up to 4 per file, in declared order) — the on-target
mirror of the host `mkasm.sh`, letting a hand-asm command share the same helper
includes (`stdin`/`glob`/`globx`/`regex`) that the C `//#use` shares. Both the
`SRC` and `OUT` arguments are **path-aware** (a full path, not a 12-char
root-only name), so a source under `/src` can be assembled straight into a
build-output dir: `asm /src/commands/asm/pwd.asm /src/commands/asm/bin/pwd.bin`.
Together these let ASM rebuild the hand-asm `/bin` commands from source on the
machine — the `asm` half of the on-target rebuild loop (`cc` handles the C
half); the `make`/`sh` built-ins drive it (see
[os/commands/](../os/commands/README.md)).

The opcode table is **generated** from `genucode.OPC` by
`generators/gen_p8xopc.py` and concatenated after the assembler logic at build
time, so the mnemonic/encoding map can never drift from the microcode.

Source and output are both **streamed to/from disk** through the BIOS file
streams — input via `FOPEN`/`FGETB` (a line at a time), output via
`FWOPEN`/`FPUTB`/`FCLOSE` (a sector at a time). So source and output size are
bounded by the disk, not RAM, and the freed RAM gives a large (~850-entry)
symbol table. As a result the assembler can **assemble its own
source** on-target, producing a binary byte-identical to the host build
(`emulator/test/asm_selfhost_test.sh`, `make test-asm-selfhost`).

Correctness is checked by assembling a feature source both on-target and with
the host assembler and comparing the bytes (`emulator/test/os_asm_test.sh`).
Limits: ~850 symbols, 12-char names, 127-char source lines, single `.org`
(use `.org $6A00`; a backward `.org` is rejected).

## CC — native C compiler (`p8xcc.asm`)

A from-scratch, single-pass C compiler written directly in assembly — small
enough (~21 KB) to compile C **entirely on the machine**, front and back end.
It streams the source in (BIOS `FOPEN`/`FGETB`, one-char pushback) and emits P8X
assembly to stdout (`SYS_PUTC`, shell-redirectable), which the native `asm`
turns into a RUNnable binary — so C is compiled, assembled, and run on-target:

```
cc hello.c >hello.asm      # native compiler
asm hello.asm HELLO.BIN    # native assembler
run HELLO.BIN
```

This is **Milestone B** (the native route) — the optimizing host `p8cc.c`
codegen is ~82 KB, larger than the whole 64 KB address space, so it can't run on
the machine; `cc` uses a deliberately small hardware-stack codegen instead.

**Language (through v0.28):** functions, direct **and mutual** recursion (via a
forward prototype), pointers + pass-by-reference, `int`/`char`, arrays with `[]`
and name decay, **structs** (`.`/`->`), file-scope globals, the full operator set
(`+ - * / % << >> & ^ | && || ?:`, `++ -- += -=`, comparisons, unary `- ! * &`),
hex/char/string literals with escapes, `//` and `/* */` comments, a recursive
**`//#use`** preprocessor (splices `/lib/lib_*.c`) plus object-like **`//#define`**
macros, and the `putchar`/`puts`/`getchar`/`peek`/`poke`/`argstr`/`bios` builtins.
It compiles real OS command
source (e.g. `pwd.c`). Codegen is verified **behaviourally** (compile → asm →
run → diff output; `emulator/test/os_cc_test.sh`).

Known gaps are listed under "cc — KNOWN LIMITATIONS" in [`BACKLOG.md`](../BACKLOG.md)
(highlights: 16-bit `int` only; no `unsigned`/`typedef`/`enum`/`union`/`sizeof`;
struct member names must be unique program-wide, no struct params/returns; `+`
doesn't scale pointers by element size; preprocessor is `//#use` + object-like
`//#define` only — no `#include`/`#if`/function-like macros).
