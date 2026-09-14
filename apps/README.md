# P8X applications

Standalone **TPA programs** — assembled to load and execute at `$5900` (the
transient program area), launched from P8X/OS with `RUN`. Each is built entirely
on the BIOS jump table (`$0100..`); none depend on OS internals, so they return
to the shell with a plain `RTS`.

Build one with the host assembler and place it on a disk:

```sh
python3 assembler/p8xasm.py apps/p8xedit.asm -o edit.bin --base 0x5900
python3 tools/p8xfs.py put disk.img edit.bin --name /BIN/EDIT.BIN --load 0x5900 --exec 0x5900
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

A file larger than that buffer is **refused** — `FILE TOO LARGE (MAX 12K)`, and
EDIT returns to the OS without a buffer or a filename. It deliberately does not
load the first 12 KB: a part-loaded file is indistinguishable from a short one,
and the first `W` would write it back over the original. Input lines are capped
at 255 characters (`LBUF` is one page at `$BE00`, and the editor's own state
begins at `$BF00`).

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
base `$5900` — so a program written `.org $5900` is **directly RUNnable** right
after assembling it. Pair with `EDIT` for a complete on-target edit → assemble →
run loop.

Accepted syntax is a subset of the host assembler, with identical encodings:

| form | example |
|------|---------|
| label | `loop:` |
| equate | `COUNT = 3` |
| instruction | `LDA #COUNT` · `STA $C000` · `LDA (P1)+` · `JSR done` |
| two-operand forms | `MOVW __ax,__V+4` · `ADDW __ax,__t0` · `CMPW __ax,#300` · `LDW __V+2,(P3+3)` · `STW (P3+1),__ax` — since 2026-09-12 the native parser handles every Tier A shape the host assembler does (`a,b`, `a,#imm8`, `a,#imm16`, `(Pn+d)`, `a,(Pn+d)`, `(Pn+d),a`; `PARSEOP`/`CLASSOP`, byte-literal rule `LIT8` = the host's), so `cc`'s output and hand sources assemble byte-identically on both. Only the relative branches (`.relax`/`.R`) stay host-only |
| `LDPn #imm16` | `LDP1 #msg` → the 3-byte `LDPn` opcode (`$38`–`$3A`) + imm16 (Tier A; was the `LPLn`/`LPHn` pair) |
| directives | `.org .byte .word .ascii .asciiz .fill` — a string decodes `\n \t \r \0` and `\\ \" \'` as the host assembler does (since 2026-09-13; the on-board `cc` emits C escapes raw for the assembler to decode) |
| expressions | `$hex` · decimal · `'c'` · symbol, joined with `+`/`-`, optional `<`/`>` prefix |

A `;#use NAME` line (at column 0) appends the shared include `/lib/NAME.inc`
after the program body (up to 4 per file, in declared order) — the on-target
mirror of the host `mkasm.sh`, letting a hand-asm command share the same helper
includes (`stdin`/`glob`/`globx`/`regex`) that the C `//#use` shares.

> **`;#use` is live here but inert host-side.** The host `assembler/p8xasm.py`
> sees the leading `;` and skips the line as an ordinary comment; only this
> assembler acts on it. So a source spliced host-side must not keep the
> directive, or the on-target build hunts for an include that isn't on the disk
> while host builds stay green — `mkasm.sh` therefore rewrites the line as it
> splices. The same asymmetry applies to any `;`-prefixed pseudo-directive:
> reproduce toolchain bugs **on-target**, not just on the host. Both the
`SRC` and `OUT` arguments are **path-aware** (a full path, not a 12-char
root-only name), so a source under `/src` can be assembled straight into a
build-output dir: `asm /src/commands/asm/pwd.asm /src/commands/asm/bin/pwd.bin`.
Together these let ASM rebuild the hand-asm `/bin` commands from source on the
machine — the `asm` half of the on-target rebuild loop (`cc` handles the C
half); the `sh` built-in drives it (see
[os/commands/](../os/commands/README.md)).

The opcode table is **generated** from `genucode.OPC` by
`generators/gen_p8xopc.py` and concatenated after the assembler logic at build
time, so the mnemonic/encoding map can never drift from the microcode.

Source and output are both **streamed to/from disk** through the BIOS file
streams — input via `FOPEN`/`FGETB` (a line at a time), output via
`FWOPEN`/`FPUTB`/`FCLOSE` (a sector at a time). So source and output size are
bounded by the disk, not RAM, and the freed RAM gives a large symbol table
(1,664 entries at `$8000`–`$E7FF`). As a result the assembler can **assemble
its own source** on-target, producing a binary byte-identical to the host build
(`emulator/test/asm_selfhost_test.sh`, `make test-asm-selfhost`).

Correctness is checked by assembling a feature source both on-target and with
the host assembler and comparing the bytes (`emulator/test/os_asm_test.sh`).
Limits: 1,664 symbols, 12-char names, 127-char source lines, single `.org`
(use `.org $5900`; a backward `.org` is rejected).

**Redesigned for the Tier A ISA (2026-09-12).** `p8xasm.asm` was rewritten
from scratch as a drop-in (same syntax, same error messages, byte-identical
output; the four `os_asm*`/`asm_selfhost` tests lock it to the host): 16-bit
values are word variables handled with `ADDW`/`SUBW`/`CMPW`/`INCW`/`MOVW`; the
symbol table is a 256-bucket **chained hash** of 16-byte entries (`name[12]
value[2] next[2]`) read and written through `(P2+d)` — `LDW CNT,(P2+12)` fetches
a value in one instruction — instead of a linear scan comparing all 12 bytes of
every entry; the opcode table gets a first-letter index at startup so a mnemonic
lookup scans only its letter group, shape byte first; operand emission is a
jump table (`DISPTAB` + `LPW1`/`JSR (P1)`); `MOVW` and `LDPn` need no special
cases (a lone `#` that fails as imm8 is retried as imm16); `.org` pads forward
itself so `EMIT` is a plain write-and-`INCW`; fixed-size copies are `MOVW`/`STW`
runs. Binary 5,178 → 4,065 B. Cycles (`p8xemu -L`): the coverage source 6.40 M →
2.62 M (2.4×), assembling its own source 282 M → 49.5 M (5.7×), a 1,000-symbol
stress source > 900 M (did not finish) → 29 M. The code + opcode table must
stay below `$8000` (the table start); `os_asm_test.sh` asserts it.

**The C version (`asm.c`, 2026-09-13) — size and speed against the asm one.**
`apps/asm.c` is the same assembler in the p8cc subset: same syntax, error
messages and output, the same raw-memory map above the image (source and
include sectors, path buffers, chain heads). Built by the host toolchain — the
opcode table as C (`opctab.c`, from `gen_p8xopc.py --c`) concatenated ahead of
the source, `//#use abi` spliced, `p8cc.py` — and installed as `/binc/asm.bin`;
`emulator/test/asm_c_test.sh` assembles the coverage source, the feature
program, a `;#use` command, a relative `.include` and the asm assembler's own
source with it, all byte-identical to the host.

| | asm `p8xasm.asm` | C `asm.c` | ratio |
|---|---|---|---|
| binary | 4,116 B | 9,945 B | 2.4× |
| the all-opcode coverage source | 2.62 M cycles | 11.0 M | 4.2× |
| its own 71 KB source (self-host) | 49.5 M | 194 M | 3.9× |
| symbol capacity | 1,664 | 480 (the table starts above the larger image, at `$A800`) | |

Tuned for the compiler like the C BASIC (an add-only hash instead of a 7-step
shift per character, the identifier scan and the byte loop inlined), which
took it from 4.7× to the figures above. The remaining gap is the per-call frame
and the byte-at-a-time pointer walks the compiler emits around every `bios`
byte in and out.

## CC — native C compiler (`p8xcc.asm`)

A from-scratch, single-pass C compiler written directly in assembly — small
enough (~10 KB) to compile C **entirely on the machine**, front and back end.
It streams the source in (BIOS `FOPEN`/`FGETB`, one-char pushback) and emits P8X
assembly to stdout (`SYS_PUTC`, shell-redirectable), which the native `asm`
turns into a RUNnable binary — so C is compiled, assembled, and run on-target:

```
cc hello.c >hello.asm      # native compiler
asm hello.asm HELLO.BIN    # native assembler
run HELLO.BIN
```

This is **Milestone B** (the native route) — the host `p8cc.c` codegen compiles
to far more than the 64 KB address space (its tables are host-sized), so it
can't run on the machine; `cc` uses a deliberately small static-slot codegen
instead.

**Tier A output (2026-09-12).** `cc` now emits the new instructions: a literal is
`LDW __ax,#n`, `+ - & | ^` are `ADDW`/`SUBW`/`ANDW`/`ORW`/`XORW` on the `__ax`/`__t0`
words, a struct offset is `ADDW __ax,#k`, `++`/`--` are `INCW`/`DECW` in place, a
condition test is `CMPW __ax,#0`, an ordering is one `CMPW` and one branch (only
`==`/`!=` still call the 16-bit `__cmp`), unary minus is `XORW #65535`/`INCW`.
Arguments no longer go through the software arg stack: the caller pushes them
left to right with `PHW`, the callee copies them into its static slots with
`LDW __V+2s,(P3+d)` (arg *i* at `P3+3+2(n-1-i)`), and the caller drops them
with `ADDP3`; the caller's live-slot saves (re-entrancy) now precede the
arguments and are discarded rather than restored when an argument took an
address. Programs start like `p8cc`'s: the caller's `P3` is kept in `__sp0` and
the program runs on a stack below `CSTACKTOP` unless launched nested. The
`__add`/`__sub`/`__and`/`__or`/`__xor`/`__neg`/`__pusharg`/`__pop` runtime texts
are gone. **Condition mode:** `if`/`while`/`for` hand `GEXPR` a false-label
(`CONDF`/`CONDLBL`); a relational that ends the condition emits its compare and
ONE branch to that label (`EMITCF`) instead of a 0/1 value and a re-test, and
the statement skips its own `CMPW #0`/`JZ` (`CONDDONE`). A nested `GEXPR`
(call arguments, parentheses, an index) sees the flag cleared and still
produces a value. A statement-level `NAME++`/`NAME--` is one `INCW`/`DECW` on
the slot. Results on the same test program compiled and run on the board:
5,546 → 2,041 bytes (−63%), identical output; `vi.c` built on the board
26,632 → 25,228 bytes. For scale, the Python compiler makes 1,066 bytes of the
same (subset) program and the C-written host compiler 1,107: the on-board
compiler's static-slot model and single pass cost about 2× in size, by design.
**The compiler's own body** went through `tools/tierA_rewrite.py` too (88 word
moves / pointer loads / carry chains → one instruction each; `cc.bin`
22,924 → 20,905 bytes including the new condition-mode code), as did the
assembler's (36 sites; verified byte-identical by `asm_selfhost_test`).

**Rewritten from scratch for the Tier A ISA (2026-09-13).** `p8xcc.asm` is a
drop-in: the code it GENERATES is the same instruction for instruction (checked
by compiling the spliced `pwd`, `wc`, `grep` and `vi` sources with the old and
the new compiler on the machine and diffing the text; only the indentation of
the emitted lines changed, from eight spaces to one tab, which makes the output
about 35% smaller and the following `asm` step correspondingly quicker). What
changed inside: every name table (locals, globals, functions, macros, struct
tags and members, spliced libraries) is one mechanism — arena entries
`[next][len][flag][value][chars]` chained from a 32-way first-letter head
array, read and written through `(P1+d)`, an entry rejected on its length
before a character is compared (the old packed pools walked every name byte by
byte, and every identifier paid that for the macro table alone); the lexer
classifies keywords once (`KWFIND` → `CURKW`) instead of the parser running up
to ten string compares per statement; slot numbers, literals and the decimal
emitter use the word ops; emitted text is walked with one pointer (the OS's
`SYS_PUTC` preserves it); the tables live at `$B000`–`$DFFF` (free TPA while the
compiler runs, cleared at start) so the binary is code only. `cc.bin` 20,915 →
10,075 bytes (the old file carried 7.6 KB of tables as zeros; code alone
13.3 KB → 10.1 KB). Compile cycles on the machine: `pwd.c` 2.60 M → 2.10 M,
`wc.c` 30.8 M → 20.6 M, `grep.c` 55.8 M → 36.1 M, `vi.c` 48.8 M → 30.0 M (1.2–1.6×,
the rest being the BIOS byte stream and `SYS_PUTC` themselves). Three
behaviour changes, all fixes: a `char` array declared after an `int` array in
the same function was compiled with word elements (the differential run caught
it in `grep.c`'s `collect`; `puts` of such an array printed one character),
a call to a function not yet declared now emits its name (the assembler resolves
it) instead of a garbage label, and a syntax error stops with `cc: syntax
error` instead of looping. Limits (raised later the same day, for the C twin
below): 250 functions, 250 `//#define`s, 5 nested `//#use`; the arenas hold
11.5 KB of global names (the tables now start at `$A000`) and 768 bytes of
locals per function (`cc: symbol table full` past that).

**Three more fixes (2026-09-13, found by diffing the C twin's output against
this compiler's on the machine):** the right operand of `&&` now leaves
condition mode — `if (a && b == c)` emitted the relational's single branch and
then fell into the body when `a` was false (`||` was always right; the `&&`
form is what real sources use, e.g. `while (*a && *a == *b)`); label numbers
are 16-bit — the byte counter wrapped at 256, so any on-board build of
`grep.c` (600 labels) or `vi.c` (353) got duplicate labels; and a local
array's size is 16-bit arithmetic — `char b[300]` was given 21 slots instead
of 150. `cc.bin` 10,075 → 10,182 bytes. `cc_c_test.sh` guards all three.

**The C version (`cc.c`, 2026-09-13) — size and speed against the asm one.**
`apps/cc.c` is the same compiler in the p8cc subset, mirroring `p8xcc.asm`
routine for routine: the same static-slot codegen, the same name-table
mechanism (arena entries chained from first-letter heads, as raw memory above
the image from `$B800`), the same messages and — the point — the same emitted
text. `emulator/test/cc_c_test.sh` compiles six sources with both compilers on
the machine and diffs the text (that differential is what found the three
bugs above); compiling `cc.c` itself with both gives 136,032 identical bytes.
Built by the host toolchain (`//#use abi` spliced, `p8cc.py`) as `/binc/cc.bin`.

| | asm `p8xcc.asm` | C `cc.c` | ratio |
|---|---|---|---|
| binary | 10,182 B | 18,089 B | 1.8× |
| `pwd.c` | 2.09 M cycles | 4.54 M | 2.2× |
| `wc.c` | 20.6 M | 37.7 M | 1.8× |
| `vi.c` | 30.2 M | 54.4 M | 1.8× |
| `cc.c` (its own source) | 68.0 M | 130.2 M | 1.9× |

The gap is the smallest of the three twins (BASIC 3.6–4.9×, the assembler
3.9–4.2×) because both compilers spend most of their cycles in the BIOS byte
stream and `SYS_PUTC`. The source keeps to the subset BOTH compilers accept
(no `break`/`continue`, no initialised globals, no string literal over 127
characters, byte stores through pointers written `p[0] = v` because the
on-board compiler stores a word through `*p =`), so the on-board compiler
compiles it — and **the self-hosting round trip now WORKS** (2026-09-14): `cc.c`
uses the P3-stack-frame codegen (recursion-correct, ~13% smaller), which brings
its self-compile to 30,843 bytes; the native assembler assembles that (its
symbol table grew 1,120 → 1,664 for the 1,548-symbol output), and the
self-compiled compiler **runs and reproduces its own output byte-for-byte** — a
fixed point. It took the frame model plus the +2 KB of TPA (the ROM 8K → 6K
reclaim dropped `TPABASE` to `$5900`) plus a raised table layout so the 30.8 KB
image clears its own tables. Regression test: `emulator/test/cc_selfhost_test.sh`.

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
