# P8X BASIC — Programmer's Guide

P8X BASIC is a small integer BASIC that runs on the P8X TTL CPU, written in P8X
assembly (`p8xbasic.asm`) and assembled by `p8xasm.py`. It talks to you over the
6850 ACIA serial console. This guide documents the language **as implemented** —
if something isn't listed here, it isn't supported yet (see *Limits*).

> Source of truth: `basic/p8xbasic.asm`. The companion [README](README.md) covers
> build internals and milestones; this is the language reference.

## Running it

From the repo root:

```sh
./basic/run.sh
```

That assembles BASIC, builds the microcode, compiles the emulator, and drops you
at a live prompt. Type lines and press **Enter**. Quit with **Ctrl-C** (or
**Ctrl-D**). The terminal runs raw/no-echo (BASIC echoes), so it behaves like a
real serial console.

### Versions of BASIC

The same interpreter ships three ways (identical language; they differ only in
where the code and its data live and how you start it):

| Build | Code | Data | Invoked by |
|-------|------|------|------------|
| Standalone | `$0000` | `$8000` | burned as the whole ROM; `run.sh` / tests |
| ROM-in-monitor | `$2000` | `$A000` | the monitor's `X` command; type `BYE` to return to the monitor |
| Disk | `$8000` | `$A000` | a bootable P8XFS image, started with the monitor's `B` command |

`Code` is where the interpreter runs and `Data` is the base of its variables and
program storage; everything else about the language is the same. From the
monitor, **`X`** drops into ROM BASIC and **`BYE`** comes back; a BASIC disk
boots with **`B`**. Build commands for the disk and ROM images are in the
[README](README.md#three-build-targets-one-source).

## The two modes

- **Immediate mode** — a line with *no* leading line number runs at once:
  ```
  PRINT 2+3*4      ->  14
  LET A=10 : PRINT A*A   ->  100
  ```
- **Program mode** — a line that *starts with a number* is stored, not run:
  ```
  10 PRINT "HELLO"
  20 GOTO 10
  ```
  Type `RUN` to execute the stored program.

### Editing a program

| You type | Effect |
|----------|--------|
| `30 PRINT X` | insert line 30 (or **replace** it if it exists) |
| `30` (number alone) | **delete** line 30 |
| `LIST` | print the program in line-number order |
| `NEW` | erase the whole program |

Lines are always kept sorted by number regardless of entry order. Keywords are
tokenized on entry (stored as single bytes) and expanded again by `LIST`.

## Numbers, variables, strings

- **Numbers** are **signed 16-bit integers**, range **−32768 to 32767**, written
  in decimal *or* hex with a `0x` prefix (`0x1F`, `0xFF`, up to `0xFFFF`).
  Arithmetic wraps modulo 65536, so `0xFFFF` prints as `-1`.
- **Variables** have **names** that start with a letter and continue with
  letters or digits (e.g. `X`, `I`, `COUNT`, `X1`, `TOTAL`). Names are
  case-insensitive and **significant to 6 characters** (`COUNTER` and `COUNTED`
  are the same variable); up to 32 distinct variables. Each holds one integer
  and starts at 0 on first use. A name may begin with a keyword (`TOTAL`,
  `FORK`) as long as it's followed by more letters/digits — `TO X` is the `TO`
  keyword, `TOTAL` is a variable. (No arrays.)
- **Strings** exist only as **literals inside `PRINT`** (`PRINT "HI"`). There are
  no string variables.

## Expressions

Operators, highest precedence first:

| Level | Operators | Notes |
|-------|-----------|-------|
| unary | `-` `+` | `-5`, `--A` (both apply to the following factor) |
| 1 | `*` `/` `%` | integer multiply / divide (`/` truncates toward zero) / modulus (remainder of `/`) |
| 2 | `+` `-` | add / subtract |
| 3 | `=` `<>` `<` `>` `<=` `>=` | comparisons; yield **1** (true) or **0** (false) |

Parentheses override precedence: `(2+3)*4` → 20. Comparisons are signed and can
be used anywhere a number can: `PRINT 5>3` prints `1`; `LET F = A<0`.

### Functions

| Call | Returns |
|------|---------|
| `ABS(x)` | absolute value of `x` |
| `RND(n)` | a pseudo-random integer **1..n** (LCG; `RND(6)` is a die) |
| `PEEK(addr)` | the byte (0–255) at memory address `addr` |

`POKE addr,val` is a *statement* (below), not a function.

## Statements

A line may hold several statements separated by `:` —
`A=1 : B=2 : PRINT A+B`.

| Statement | Meaning |
|-----------|---------|
| `PRINT items` | print numbers/strings (see below); empty `PRINT` = blank line |
| `LET v = expr` | assign; the `LET` is optional, so `A=5` works too |
| `IF expr THEN ...` | if `expr` is non-zero, run the rest of the line; the `THEN` part may be a statement (`THEN PRINT X`) **or** a line number (`THEN 100`, an implicit `GOTO`) |
| `FOR v = a TO b [STEP s]` | begin a counting loop (`STEP` defaults to 1; negative start/limit OK) |
| `NEXT [v]` | end of loop body: add the step, loop back if still ≤ limit |
| `GOTO line` | jump to `line` |
| `GOSUB line` | call a subroutine; execution resumes after the `GOSUB` on `RETURN` |
| `RETURN` | return from the most recent `GOSUB` |
| `INPUT v` | print `? ` and read a number from the console into `v` |
| `REM text` | comment; the rest of the line is ignored |
| `END` | stop the running program |

### PRINT details

Items are separated by `,` or `;`:
- `;` — no space between items.
- `,` — one space between items.
- A **trailing** `;` or `,` suppresses the newline (so the next `PRINT`
  continues the same line).

```
PRINT "X="; X            ->  X=42
PRINT 1, 2, 3            ->  1 2 3
FOR I=1 TO 3 : PRINT I; : NEXT   ->  123
```

## Commands (immediate mode)

`RUN` (execute the stored program from the lowest line), `LIST`, `NEW`,
`HELP` (print the supported statements, commands, functions, and operators),
and `BYE` (leave BASIC — returns to the monitor in the ROM/disk builds).

## Memory & hardware access

`PEEK`/`POKE` reach the full memory map (addresses in decimal):

| Address (dec / hex) | What |
|---------------------|------|
| 0–16383 / `$0000–$3FFF` | EEPROM (the interpreter ROM — read-only; 16 KB on rev-D hardware) |
| 16384–65279 / `$4000–$FEFF` | RAM, 48 KB (BASIC's program + variables live around `$8000`/`$A000`) |
| 65280 / `$FF00` | switch input port (`PEEK`) |
| 65282 / `$FF02` | LED output port (`POKE`) |
| 65284–65285 / `$FF04–05` | 6850 ACIA status / data |

So `POKE 65282, 170` lights an LED pattern, and `PRINT PEEK(65280)` reads the
switches. **Caution:** BASIC keeps its program and variables in low RAM
(around `$8000–$82xx`); poking there can corrupt your program.

## Examples

Countdown:

```
10 LET I=5
20 PRINT I
30 LET I=I-1
40 IF I>0 THEN 20
50 END
```

Sum 1..N with INPUT and a loop:

```
10 INPUT N
20 LET S=0
30 FOR I=1 TO N
40 LET S=S+I
50 NEXT
60 PRINT "SUM="; S
```

Subroutine called from a loop (prints 1, 4, 9, 16, 25, one per line):

```
10 FOR I=1 TO 5 : GOSUB 100 : NEXT
20 END
100 PRINT I*I
110 RETURN
```

Guess-a-number (uses RND and INPUT):

```
10 LET T=RND(100)
20 INPUT G
30 IF G=T THEN PRINT "GOT IT" : END
40 IF G<T THEN PRINT "LOW"
50 IF G>T THEN PRINT "HIGH"
60 GOTO 20
```

## Error messages

| Message | Cause |
|---------|-------|
| `?` | unrecognized statement/command |
| `?SYNTAX ERROR` | malformed expression or statement (e.g. unbalanced `)`) |
| `?UNDEF'D LINE` | `GOTO`/`GOSUB` to a line that doesn't exist |
| `?RETURN WITHOUT GOSUB` | `RETURN` with no matching `GOSUB` |

On any error the running program stops and returns to the prompt.

## Limits (current implementation)

- Integers only (16-bit signed); no floating point.
- Variables: integer only, names ≤ 6 significant chars, up to 32; no arrays,
  no string variables.
- `FOR` loops nest **2 deep**; `GOSUB` nests **3 deep**.
- No `DATA`/`READ`, `DIM`, `DEF FN`, `ON…GOTO`, `WHILE`, string functions, or
  file/disk I/O.
- Numbers are decimal only on input; `PRINT` shows signed decimal.

These reflect what `p8xbasic.asm` implements today; see [README](README.md) and
the project `BACKLOG.md` for what may come next.
