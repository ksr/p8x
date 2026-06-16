# P8X BASIC

A small BASIC interpreter for the P8X, written in P8X assembly, assembled by
[`p8xasm.py`](../assembler/p8xasm.py) and run over the 6850 ACIA serial console —
the same toolchain and I/O the [ROM monitor](../firmware/p8xmon.asm) uses.

> **Status: line editor (milestone 2).** `p8xbasic.asm` boots and runs a REPL
> with a working program editor: enter numbered lines (stored sorted; same
> number replaces, a bare number deletes), `LIST`, `NEW`. Line numbers are full
> 16-bit integers. Verified in the emulator. Tokenizing and execution (`RUN`,
> statements, expressions) are the next milestones.

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

```sh
# from the repo root
python3 assembler/p8xasm.py basic/p8xbasic.asm -o /tmp/basic.bin
(cd microcode && python3 genucode.py)      # build u0-u3.bin microcode
cp microcode/u?.bin .                       # emulator loads u?.bin from its cwd
emulator/p8xemu /tmp/basic.bin
```

(The emulator reads the ACIA from stdin and writes to stdout, so you type BASIC
lines straight into the terminal. Use a cycle cap `-l N` to bound EOF spin. Try:
`printf '20 PRINT "B"\r10 PRINT "A"\rLIST\r' | emulator/p8xemu -l 8000000 /tmp/basic.bin`)

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
3. **Expression evaluator** — integer `+ - * /`, parens, variables, comparisons.
4. **Statements** — `PRINT`, `LET`, `GOTO`, `IF/THEN`, `GOSUB/RETURN`, `END`,
   `INPUT`, `RUN`.
5. **Polish** — error messages, `REM`, multi-statement lines, `RND`/`PEEK`/`POKE`.

## Open decisions

Settled: dialect = richer MS-style subset; numbers = integer-only. Still open:

- **Storage** — store source text verbatim, or tokenize keywords to single bytes?
  (Tokenizing saves space and speeds the run loop; decide at milestone 2.)
- **Relationship to the system** — standalone ROM image (current, easiest to test),
  vs launched from the monitor's `G`, vs loaded from CF by the OS.
