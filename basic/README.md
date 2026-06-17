# P8X BASIC

A small BASIC interpreter for the P8X, written in P8X assembly, assembled by
[`p8xasm.py`](../assembler/p8xasm.py) and run over the 6850 ACIA serial console —
the same toolchain and I/O the [ROM monitor](../firmware/p8xmon.asm) uses.

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
> Plus `INPUT`, multi-statement lines (`A=1 : PRINT A`), and multi-item `PRINT`
> (`PRINT A, B; C`). Single-line loops like `FOR I=1 TO 5 : PRINT I; : NEXT`
> work. Verified in the emulator. Still to come: signed integers + unary minus,
> functions (`ABS/RND/PEEK/POKE`).
>
> Limits: FOR nesting 2 deep, GOSUB 3 deep; integers are unsigned 16-bit.

## Direction

A **richer Microsoft-style subset, integer-only** (decided 2026-06-16). Line-
numbered and interactive, with immediate mode (no line number → execute now).
This fits the machine well — the pointer bank makes a text pointer (P1/P2) and
the indirect addressing modes natural for the interpreter inner loop; integers
keep it tractable on this ISA (floats are a large lift, deferred).

Target language:
- **Statements:** `PRINT`, `LET` (and implicit let), `IF/THEN`, `FOR/NEXT`,
  `GOTO`, `GOSUB/RETURN`, `INPUT`, `REM`, `END`, `RUN`, `LIST`, `NEW`
- **Lines:** multiple statements per line separated by `:`
- **Expressions:** integer `+ - * /`, parens, comparisons (`= <> < > <= >=`),
  numeric variables A–Z (and A0–Z9), plus string variables (`A$`) for PRINT/INPUT
- **Functions:** `ABS`, `RND`, `PEEK`/`POKE` (memory + I/O access — the P8X hook)

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

## Planned layout (proposed — see open decisions)

| Region | Use |
|--------|-----|
| `$0000-$7FFF` | interpreter code (EEPROM) |
| `$8000-…`     | tokenized program text |
| `…-$FDFF`     | variables (26 ints A–Z to start), string/eval scratch |
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
5. **Polish** — signed integers + unary minus, functions (`ABS/RND/PEEK/POKE`),
   `REM`. (`REM`/functions tokenize already; not yet evaluated/executed.)
5. **Polish** — error messages, `REM`, multi-statement lines, `RND`/`PEEK`/`POKE`.

## Open decisions

Settled: dialect = richer MS-style subset; numbers = integer-only;
**storage = keywords tokenized to single bytes** (≥$80), strings/text left
literal — crunch on entry, uncrunch in `LIST`. Still open:

- **Relationship to the system** — standalone ROM image (current, easiest to test),
  vs launched from the monitor's `G`, vs loaded from CF by the OS.
