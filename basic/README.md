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
> Plus `SAVE "NAME"` / `LOAD "NAME"` — programs persist to the CompactFlash
> filesystem (P8XFS v2 root) via the monitor's BIOS FS calls; ROM and disk
> builds only.
>
> Limits: FOR nesting 2 deep, GOSUB 3 deep.

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

## Four ways to build & run (one source)

BASIC is self-contained (its own ACIA console + RAM), so the *same* source
builds several ways. The differences are just `-D` symbols — `BASORG` (code
origin), `BASRAM` (data base), `PBUF` (rebuild scratch), and `MONITOR` (where
`BYE` goes). All default to the standalone values and are overridable per build.

| Build | Code (`BASORG`) | Data (`BASRAM`) | Invoked by |
|-------|-----------------|-----------------|------------|
| Standalone | `$0000` | `$8000` | burned as the whole ROM; `run.sh` / scripted tests |
| ROM-in-monitor | `$2000` | `$A000` | monitor `X` command (BASIC's `BYE` returns to the monitor) |
| Disk | `$4000` | `$A000` | installed on a P8XFS image, booted by the monitor `B` command (rev D: loads at `$4000`) |
| Run-from-OS | `$B000` | `$C500` | a TPA program (`PBUF=$E000`, `MONITOR=$4000`) installed as `BASIC.BIN`; `RUN` it from the OS, `BYE` returns to the OS (see below) |

`Code` is where the interpreter runs (low ROM, monitor ROM, or RAM); `Data` is
the base of its variables + program text; `PBUF` (rebuild scratch) defaults to
`$C000` and moves only for the TPA build. The standalone build takes no `-D` (the
source defaults are `$0000`/`$8000`/`$C000`) and is byte-identical to before this
split.

**ROM-in-monitor** — build the combined monitor+BASIC EEPROM and launch with `X`:

```sh
python3 tools/build_basic_rom.py p8x-rom-basic.bin   # monitor + BASIC @ $2000
# boot it; at the monitor '*' prompt press X to enter BASIC; type BYE to return
./emulator/p8xemu p8x-rom-basic.bin                  # (needs u0-u3.bin alongside)
```

**Disk** — assemble at `$4000` (rev D boot address), install as a bootable image, boot with `B`:

```sh
python3 assembler/p8xasm.py basic/p8xbasic.asm -o basicdisk.bin \
        --base 0x4000 -D BASORG=0x4000 -D BASRAM=0xA000
python3 tools/p8xfs.py create disk.img
python3 tools/p8xfs.py boot   disk.img basicdisk.bin
./emulator/p8xemu -c disk.img eeprom.bin             # at '*' press B
```

**Run from P8X/OS** — a fourth way: install BASIC as a regular OS program so you
can `RUN BASIC.BIN` from the OS shell and `BYE` back to it. No source change —
just relocate everything into the **TPA** (`$B000+`, clear of the OS at
`$4000–$AFFF`) and point `MONITOR` at the OS cold-start so `BYE` re-enters the OS
(which stays resident) instead of the ROM monitor:

```sh
python3 assembler/p8xasm.py basic/p8xbasic.asm -o basicrun.bin \
        --base 0xB000 -D BASORG=0xB000 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x4000
python3 tools/p8xfs.py put disk.img basicrun.bin --name BASIC.BIN --load 0xB000 --exec 0xB000
# boot the OS (B), then:  RUN BASIC.BIN   ... use BASIC ...   BYE   (-> back at /> )
```

Layout: code `$B000`–`$C48x` (~5.2 KB), data `$C500` (`PROG` at `$C700`), rebuild
buffer `$E000`; the stack stays at `$FEFF`. Covered by `os_basic_test.sh`.

All four paths are covered by `make test-basic` (in `emulator/`): ROM BASIC via
`X`, disk BASIC via `B`, `SAVE`/`LOAD` round-trip, and `RUN BASIC.BIN` from the
OS. Code is ~5.2 KB, so in every layout it clears its data base with room to spare.

## Planned layout (proposed — see open decisions)

| Region | Use |
|--------|-----|
| `$0000-$3FFF` | interpreter code (EEPROM, 16 KB rev D) |
| `$4000-$7FFF` | RAM (rev D) — unused by the standalone build |
| `$8000-…`     | tokenized program text (standalone `BASRAM=$8000`) |
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
5. **Polish** — ✅ signed integers + unary minus, `REM`, functions `ABS`,
   `RND` (LCG), `PEEK`/`POKE` (memory + memory-mapped I/O), and `SAVE`/`LOAD`
   over the filesystem.

## Open decisions

Settled: dialect = richer MS-style subset; numbers = integer-only;
**storage = keywords tokenized to single bytes** (≥$80), strings/text left
literal — crunch on entry, uncrunch in `LIST`. Still open:

- **Relationship to the system** — standalone ROM image (current, easiest to test),
  vs launched from the monitor's `G`, vs loaded from CF by the OS.
