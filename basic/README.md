# P8X BASIC

A small BASIC interpreter for the P8X, written in P8X assembly, assembled by
[`p8xasm.py`](../assembler/p8xasm.py) and run over the 6850 ACIA serial console —
the same toolchain and I/O the [ROM monitor](../firmware/p8xmon.asm) uses.

> **Status: skeleton.** `p8xbasic.asm` currently boots, prints a banner, and runs
> a read-line REPL loop (line input + echo). No tokenizing, storage, or execution
> yet — that's the work ahead. It assembles and runs in the emulator today.

## Direction

Aiming at a **Tiny-BASIC-class** interpreter (per the BACKLOG idea): integer-only,
line-numbered, interactive. This fits the machine — a few KB of ROM, the pointer
bank makes a text pointer (P1/P2) and the indirect addressing modes natural for
an interpreter inner loop.

Target language core (first milestone): `PRINT`, `LET`, `IF/THEN`, `GOTO`,
`GOSUB/RETURN`, `INPUT`, `END`, line numbers, integer expressions with `+ - * /`
and comparisons, and immediate-mode (no line number → execute now).

## Build & run

```sh
# from the repo root
python3 assembler/p8xasm.py basic/p8xbasic.asm -o /tmp/basic.bin
cd emulator && make ucode            # build u0-u3.bin microcode
cp microcode/../microcode/u?.bin .   # (the emulator loads u?.bin from its cwd)
./p8xemu /tmp/basic.bin
```

(The emulator reads the ACIA from stdin and writes to stdout, so you type BASIC
lines straight into the terminal. Use a cycle cap `-l N` to bound EOF spin.)

## Planned layout (proposed — see open decisions)

| Region | Use |
|--------|-----|
| `$0000-$7FFF` | interpreter code (EEPROM) |
| `$8000-…`     | tokenized program text |
| `…-$FDFF`     | variables (26 ints A–Z to start), string/eval scratch |
| `$FE00-$FEFF` | stack (P3), incl. GOSUB return stack |

## Milestones

1. **REPL skeleton** — banner + line input/echo. ✅ (current)
2. **Line editor** — store numbered lines in a program buffer (insert/replace/
   delete by line number), `LIST`, `NEW`.
3. **Expression evaluator** — integer `+ - * /`, parens, variables, comparisons.
4. **Statements** — `PRINT`, `LET`, `GOTO`, `IF/THEN`, `GOSUB/RETURN`, `END`,
   `INPUT`, `RUN`.
5. **Polish** — error messages, `REM`, multi-statement lines, `RND`/`PEEK`/`POKE`.

## Open decisions (to settle before milestone 2)

- **Dialect/subset** — Tiny BASIC (minimal) vs a richer Microsoft-ish subset?
- **Numbers** — integer-only to start (recommended); floats are a big lift on this ISA.
- **Storage** — store source text verbatim, or tokenize keywords to single bytes?
- **Relationship to the system** — standalone ROM image (current, easiest to test),
  vs launched from the monitor's `G`, vs loaded from CF by the OS.

These don't block the skeleton; they shape milestone 2 onward.
