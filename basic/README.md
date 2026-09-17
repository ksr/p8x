# P8X BASIC

A small BASIC interpreter for the P8X, written in P8X assembly, assembled by
[`p8xasm.py`](../assembler/p8xasm.py) and run over the 6850 ACIA serial console —
the same toolchain and I/O the [ROM monitor](../firmware/p8xmon.asm) uses.

**Using the language?** See the **[P8X BASIC Programmer's Guide](p8x-basic-guide.md)**
— statements, expressions, functions, memory access, and example programs. This
README covers build internals and milestones.

> **Status: runs programs.** Editor + tokenizer + integer expression evaluator,
> and stored programs now **execute**: `RUN`, `GOTO`, `IF…THEN <stmt|line>`,
> `END`, plus comparisons (`= <> < > <= >=`), `PRINT`, `LET`. A real branching
> program works, e.g.:
>
> ```
> 10 LET I=5
> 20 PRINT I
> 30 LET I=I-1
> 40 IF I>0 THEN 20
> 50 END
> RUN        ->  5 4 3 2 1
> ```
>
> Plus `FOR/NEXT` (with `STEP`), `GOSUB/RETURN`. A real program runs:
>
> ```
> 10 LET S=0
> 20 FOR I=1 TO 5
> 30 LET S=S+I
> 40 NEXT I
> 50 PRINT S      ->  15
> ```
>
> Plus `INPUT`, multi-statement lines (`A=1 : PRINT A`), multi-item `PRINT`
> (`PRINT A, B; C`), single-line loops, **signed 16-bit integers** with unary
> minus, `REM`, and functions `ABS`, `RND`, `PEEK`, `POKE` (memory + I/O, so
> `POKE 65282,n` drives the LED port). The full MS-style subset is in.
>
> Plus **string variables** (`A$`, 16 slots × 32 chars): assignment, `+`
> concatenation, `=`/`<>`/`<`/`>`/`<=`/`>=` comparison, `PRINT`/`INPUT`, and
> `LEN`/`ASC`/`CHR$`/`LEFT$`/`RIGHT$`/`MID$`.
>
> Plus `SAVE "NAME"` / `LOAD "NAME"` — programs persist to the CompactFlash
> filesystem via the monitor's BIOS FS calls, relative to the **current
> directory** when running under P8X/OS (a leading `/` is absolute) — and
> **data files**: `OPEN name$ [FOR] OUTPUT|INPUT`, `PRINT#`,
> `INPUT#`, `CLOSE` (one sequential channel, one value per record).
>
> Plus **graphics**, one window-space coordinate system (y UP, the PGC's,
> 480x272 RGB565 direct colour): `COLOR r,g,b` (or one packed value),
> `CLS`, `PIXELW x,y`, `LINE x0,y0,x1,y1`,
> `BOX x0,y0,x1,y1[,FILL|,NOFILL]`, `CIRCLE x,y,r[,ry][,FILL|,NOFILL]`
> (a second radius makes it an ellipse), PGC stroke TEXT out of the box
> (`MOVE3 x,y,0 : TEXT s$` -- the OS boot-loads /FONT.GL), the easy 2D
> `GTEXT x,y,size,s$`, `IMAGE x,y,name$` (P8I file, bottom-left at x,y),
> the functions `PIXELR(x,y)` (read a pixel back) and `RGB(r,g,b)` (pack a
> colour) -- and the whole PGC graphics language as native statements (man
> basic, GRAPHICS). Two scanout layers compose (drawing bitmap below, the
> alphanumeric text overlay on top): `GRAPHICSON`/`GRAPHICSOFF` and
> `TEXTON`/`TEXTOFF` flip each independently. BASIC cold-starts with GRAPHICS
> OFF (a fresh interpreter shows only its text); visibility is scanout-only,
> so drawing while hidden still lands in bitmap RAM and `GRAPHICSON` reveals
> it. No display modes, no `SCREEN`, no palette -- one geometry,
> and a pixel is its colour.
> The drawing is done by the DEVICE, so a filled box costs the same few
> instructions as an empty one. With no display fitted they print `?No display`
> instead of quietly doing nothing.
>
> Lines are **syntax-checked on entry** (balanced parens, terminated strings,
> legal statement leader), so typos are caught as you type, not at RUN.
>
> Limits: FOR nesting 3 deep, GOSUB 3 deep; one data file open at a time.
>
> **Rewritten for the Tier A ISA (2026-09-12).** `p8xbasic.asm` was redone from
> scratch as a drop-in (same tokens — the `.BAS` format — same keyword table,
> messages, HELP and GL byte streams; every `make test-basic` test passes
> unchanged): statements and functions dispatch through tables indexed by the
> token (`STMTTAB`/`FACTAB`, and `CHECKLINE` reads the same table to decide what
> may start a statement), the evaluator pushes its running value with `PHW`/`PLW`
> and does its arithmetic with the word ops, a comparison is one `CMPW` plus a
> relation mask shared by numeric and string compares, variables and FOR/GOSUB
> frames are records addressed with `(P1+d)`, and the line search stops as soon
> as the sorted program passes the target. 11,151 → 9,124 bytes; cycles
> (`POKE 65282,n` stamps, `p8xemu -L`): a 2,000-iteration arithmetic loop
> 26.2 M → 16.5 M, a GOSUB/12-variable loop 37.7 M → 18.9 M, a string
> concat/compare loop 16.3 M → 5.8 M. Behaviour changes, all deliberate: FOR
> nests 3 deep (was 2, unchecked), a 4th GOSUB or a 33rd variable is a
> `?SYNTAX ERROR` instead of silent corruption, lowercase variable names work
> at the start of a statement, and a statement after `RUN` on the same line is
> no longer misparsed.

## Direction

A **richer Microsoft-style subset, integer-only** (decided 2026-06-16). Line-
numbered and interactive, with immediate mode (no line number → execute now).
This fits the machine well — the pointer bank makes a text pointer (P1/P2) and
the indirect addressing modes natural for the interpreter inner loop; integers
keep it tractable on this ISA (floats are a large lift, deferred).

Target language:
- **Statements:** `PRINT`, `LET` (and implicit let), `IF/THEN`, `FOR/NEXT`,
  `GOTO`, `GOSUB/RETURN`, `INPUT`, `REM`, `END`, `RUN`, `LIST`, `NEW`,
  `SAVE`/`LOAD`, and data files (`OPEN`/`CLOSE`/`PRINT#`/`INPUT#`)
- **Lines:** multiple statements per line separated by `:`
- **Expressions:** integer `+ - * /`, parens, comparisons (`= <> < > <= >=`),
  named numeric variables (≤6 significant chars, up to 32), and string
  variables (`A$`: assign, `+` concat, compare) with `+` concatenation
- **Functions:** `ABS`, `RND`, `PEEK`/`POKE` (memory + I/O access — the P8X
  hook), and the string functions `LEN`, `ASC`, `CHR$`, `LEFT$`, `RIGHT$`, `MID$`

## Build & run

**Interactive — type BASIC at a live prompt:**

```sh
./basic/run.sh
```

This assembles the interpreter, builds the microcode, compiles the emulator, and
launches it attached to your terminal. The emulator detects the TTY and runs the
console in raw/blocking mode (no cycle cap, no busy-spin), so you can type lines
directly. Quit with Ctrl-C, or Ctrl-D at the prompt.

**Scripted — pipe a session (for tests/demos):**

```sh
python3 assembler/p8xasm.py basic/p8xbasic.asm -o /tmp/basic.bin
(cd microcode && python3 genucode.py)       # build u0-u3.bin
cp microcode/u?.bin /tmp/
printf '20 PRINT "B"\r10 PRINT "A"\rLIST\r' | (cd /tmp && \
    "$OLDPWD/emulator/p8xemu" -l 8000000 basic.bin)
```

Lines are terminated by CR (`\r`). In scripted mode use a cycle cap `-l N` to
bound the spin after end-of-input.

## Three ways to build & run (one source)

BASIC is self-contained (its own ACIA console + RAM), so the *same* source
builds several ways. The differences are just `-D` symbols — `BASORG` (code
origin), `BASRAM` (data base), `PBUF` (rebuild scratch), and `MONITOR` (where
`BYE` goes). All default to the standalone values and are overridable per build.

| Build | Code (`BASORG`) | Data (`BASRAM`) | Invoked by |
|-------|-----------------|-----------------|------------|
| ~~Standalone~~ | `$0000` | `$8000` | **RETIRED (2026-08-13)** — see the note below |
| Disk | `$2000` | `$A000` | installed on a P8XFS image, booted by the monitor `B` command (rev E: loads at `$2000`) |
| Run-from-OS | `$5900` | `$C500` | a TPA program (`PBUF=$E000`, `MONITOR=$2000`) installed as `BASIC.BIN`; `RUN` it from the OS, `BYE` returns to the OS (see below) |

> **The standalone build no longer works.** BASIC's `PUTC`/`GETC` now tail-call the
> BIOS (`CONOUT` `$0103` / `CONIN` `$0100`) instead of driving the ACIA directly,
> so it needs the monitor resident at `$0000-$1FFF` — which the `$0000` build
> replaces. Nothing had built that variant for some time (every target passes
> `-D BASORG=$2000` or `$5900`, and `build_rom.sh` states BASIC is no longer
> ROM-resident), so this formalises an existing state rather than removing a
> capability. The source defaults are still the `$0000` values; restoring the
> target would mean giving BASIC back its own console routines.

`Code` is where the interpreter runs (low ROM or RAM); `Data` is
the base of its variables + program text; `PBUF` (rebuild scratch) defaults to
`$C000` and moves only for the TPA build. The standalone build takes no `-D` (the
source defaults are `$0000`/`$8000`/`$C000`) and is byte-identical to before this
split.

> **ROM-in-monitor is gone.** BASIC used to be overlaid into the monitor EEPROM
> at `$2000` and launched with the monitor `X` command. Since it also ships as a
> disk program, the ROM copy was redundant and was removed to reclaim ROM space;
> use the **Disk** or **Run-from-OS** build below.

**Disk** — assemble at `$2000` (rev E boot address), install as a bootable image, boot with `B`:

```sh
python3 assembler/p8xasm.py basic/p8xbasic.asm -o basicdisk.bin \
        --base 0x2000 -D BASORG=0x2000 -D BASRAM=0xA000
python3 tools/p8xfs.py create disk.img
python3 tools/p8xfs.py boot   disk.img basicdisk.bin
./emulator/p8xemu -c disk.img eeprom.bin             # at '*' press B
```

**Run from P8X/OS** — the primary way to use BASIC: install it as a regular OS
program so you can `RUN BASIC.BIN` from the OS shell and `BYE` back to it. No source change —
just relocate everything into the **TPA** (`$5900+`, clear of the OS at
`$2000–$AFFF`) and point `MONITOR` at the OS cold-start so `BYE` re-enters the OS
(which stays resident) instead of the ROM monitor:

```sh
python3 assembler/p8xasm.py basic/p8xbasic.asm -o basicrun.bin \
        --base 0x5900 -D BASORG=0x5900 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x2000
python3 tools/p8xfs.py put disk.img basicrun.bin --name BASIC.BIN --load 0x5900 --exec 0x5900
# boot the OS (B), then:  RUN BASIC.BIN   ... use BASIC ...   BYE   (-> back at /> )
```

Layout: code `$5900`–`$8DAx` (~8.9 KB), data `$C500` (`PROG` at `$CA80`), rebuild
buffer `$E000`; the stack stays at `$FEFF`. Covered by `os_basic_test.sh`.

These paths are covered by `make test-basic` (in `emulator/`): disk BASIC via
`B`, `SAVE`/`LOAD` round-trip, string variables/functions, data-file I/O, and
`RUN BASIC.BIN` from the OS. Code is ~8.9 KB, so in every layout it clears its
data base with room to spare.

## The C version (`basic.c`) — size and speed against the asm one

`basic/basic.c` is the same interpreter written in C (2026-09-13): same
language, tokens (the `.BAS` format), messages, prompts, limits and GL byte
streams, and it keeps its big tables in the same raw memory the asm build uses
(`$C600` variables … `$CA80` program, `$E000` rebuild scratch), so both binaries
are code plus a little data. It is built by the host toolchain — the generated
GL verb tables (`glkwtab.c`, from `generators/gen_glkw.py`) concatenated ahead
of the source, `//#use abi` spliced by `clib.py`, compiled by `p8cc.py` — and
installed as **`/binc/basic.bin`**; the asm build stays the `/bin` default.
`emulator/test/basic_c_test.sh` (in `make test-basic`) runs the same programs
the asm tests use against it, and a 250-line scripted session diffs identically
between the two.

| | asm `p8xbasic.asm` | C `basic.c` | ratio |
|---|---|---|---|
| binary | 9,124 B | 21,393 B | 2.3× |
| 2,000-iteration arithmetic loop (`S=S+I*3-I/2`) | 16.5 M cycles | 59.6 M | 3.6× |
| 400 iterations of GOSUB + 12 variables + IF | 18.9 M | 76.1 M | 4.0× |
| 300 iterations of string concat / LEFT$ / MID$ / compare | 5.8 M | 28.2 M | 4.9× |

(Cycle stamps: `POKE 65282,n` at the start and end of the program, read with
`p8xemu -L`.) The C source is written the way this compiler wants it — it has no
`break`/`continue`, `int` compares and divides unsigned (a signed BASIC compare
flips the sign bit of both sides; a `while (n >= 0)` on an int never ends),
there is no `longjmp` (an error sets a flag every parse level returns through),
and a multiply by a constant is a 16-step `__mul` loop, so the hot paths use
int-pointer loads, shifts and adds instead (`vget`/`vset`, `recnum`,
`parsedec`), and the name compare and blank skipping are inlined in the
expression path. That tuning took it from 8–13× slower to the 3.6–4.9× above;
what remains is the call overhead of the recursive-descent parser (a frame per
call) and the byte-at-a-time pointer walks the compiler emits. Note for anyone
running the two side by side: the C image reaches `$BD00`, so a BASIC program
that `POKE`s into `$A000`–`$BC00` (free under the 9 KB asm build) corrupts it.

## Planned layout (proposed — see open decisions)

| Region | Use |
|--------|-----|
| `$0000-$1FFF` | interpreter code (EEPROM, 6 KB) |
| `$2000-$7FFF` | RAM (rev E) — unused by the standalone build |
| `$8000-…`     | tokenized program text (standalone `BASRAM=$8000`) |
| `…-$FDFF`     | named numeric vars (32) + string-var table + string/eval scratch |
| `$FE00-$FEFF` | stack (P3), incl. GOSUB return stack |

## Milestones

1. **REPL skeleton** — banner + line input/echo. ✅
2. **Line editor** — store numbered lines sorted (insert/replace/delete by line
   number), `LIST`, `NEW`. ✅ (rebuild-via-scratch-buffer; 16-bit decimal I/O)
3. **Expression evaluator** — integer `+ - * /`, parens, variables (A–Z).
   ✅ recursive-descent; 16-bit mul/div helpers. Wired to immediate `PRINT`/`LET`.
4. **Statements + RUN** — execute the stored program.
   ✅ `RUN`, `GOTO`, `IF/THEN`, `END`, comparisons, `FOR/NEXT` (+`STEP`),
   `GOSUB/RETURN`, `INPUT`, multi-statement lines (`:`), multi-item `PRINT`.
5. **Polish** — ✅ signed integers + unary minus, `REM`, functions `ABS`,
   `RND` (LCG), `PEEK`/`POKE` (memory + memory-mapped I/O), and `SAVE`/`LOAD`
   over the filesystem.
6. **Strings, files, entry-time checking** — ✅ string variables (`A$`) with
   assignment/concat/comparison and `LEN`/`ASC`/`CHR$`/`LEFT$`/`RIGHT$`/`MID$`;
   sequential data files (`OPEN`/`CLOSE`/`PRINT#`/`INPUT#`); and a `CHECKLINE`
   structural syntax check applied as each line is entered.

## Open decisions

Settled: dialect = richer MS-style subset; numbers = integer-only;
**storage = keywords tokenized to single bytes** (≥$80), strings/text left
literal — crunch on entry, uncrunch in `LIST`. Still open:

- **Relationship to the system** — standalone ROM image (current, easiest to test),
  vs launched from the monitor's `G`, vs loaded from CF by the OS.

## Leaving BASIC (`BYE`)

Under **P8X/OS** (the run-from-OS build), `BYE` returns to the shell that ran it:
the current directory, any redirection, and the rest of the OS state survive.

It used to `JMP MONITOR`, which for that build is `$2000` — the OS's **COLD**
entry. Leaving BASIC therefore rebooted the OS: it reprinted the banner and put
you back in the root however deep you had `cd`'d. Since 2026-08-13 BASIC captures
the caller's stack pointer at entry (`SPSAV`) and `BYE` restores it and `RTS`es,
which is exactly how every `/bin` program returns — the OS launches them with
`JSR (P1)`.

Two consequences inside BASIC, both deliberate:

- Under the OS, BASIC **adopts the caller's stack** rather than resetting `P3` to
  `STKTOP`; resetting it would overwrite the caller's frame, including the return
  address it needs.
- `SYNERR` unwinds to that saved pointer instead of `STKTOP`, for the same reason.

The disk-boot build has no caller, so it still owns the whole stack and `BYE`
jumps to the reset vector as before.
