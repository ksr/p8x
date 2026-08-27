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

The same interpreter ships four ways (identical language; they differ only in
where the code and its data live and how you start it):

| Build | Code | Data | Invoked by |
|-------|------|------|------------|
| ~~Standalone~~ | `$0000` | `$8000` | **retired 2026-08** — BASIC's console I/O now goes through the BIOS, which this build replaces. See [README](README.md). |
| Disk | `$2000` | `$A000` | a bootable P8XFS image, started with the monitor's `B` command (rev E loads the OS region at `$2000`) |
| Run-from-OS | `$6A00` | `$C500` | a TPA program (`BASIC.BIN`); `RUN` it from the OS, `BYE` returns to the OS |

`Code` is where the interpreter runs and `Data` is the base of its variables and
program storage; everything else about the language is the same. The usual way
in is **`RUN BASIC.BIN`** from the OS (`BYE` returns to the OS); a standalone
BASIC disk also boots with the monitor's **`B`**. (BASIC is no longer in the
monitor ROM — the old `X` command was removed.) Build commands are in the
[README](README.md).

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
| `SAVE "NAME"` | write the program to a file on the CompactFlash card (`Saved`) |
| `LOAD "NAME"` | replace the program with a saved file (`Loaded`) |

Lines are always kept sorted by number regardless of entry order. Keywords are
tokenized on entry (stored as single bytes) and expanded again by `LIST`.

`SAVE`/`LOAD` store programs as files in the P8XFS filesystem (via the
BIOS filesystem calls), so they work in the **disk** and **run-from-OS** builds —
the standalone whole-ROM build has no card access and can't use them.

The name may be a **path**. A bare name (`SAVE "GAME"`) is relative to the
**current directory**, so under P8X/OS `cd SRC` then `SAVE "GAME"` writes
`/SRC/GAME`; a leading slash is absolute (`SAVE "/SRC/GAME"`, `LOAD "/SRC/GAME"`)
and works from anywhere. BASIC resolves the path through the same filesystem
resolver the OS uses, so it can save into any existing directory — make one with
`MKDIR` in the OS first.

> Before 2026-08 a bare name always went to the **root**, whatever directory you
> were in, because BASIC handed the name straight to the BIOS resolver (which
> starts at the root) without first prefixing the current directory the way the
> `/bin` commands do. The disk-boot build still resolves from the root, correctly:
> there is no OS underneath it and so no current directory to be relative to.

Each leaf name is up to 12 characters and
**case-sensitive** (`GAME` and `game` are different files). `SAVE` reports
`?Save failed` if the name exists or the disk is full, `LOAD` reports `?No file`
if it isn't found. Files created here are visible to P8X/OS (`DIR`) and the host
`p8xfs.py` too.

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
- **Strings** are sequences of characters, up to **32** long. They appear as
  **literals** (`"HI"`) and as **string variables**, whose names end in `$`
  (`A$`, `NAME$`). A string variable is a *separate* variable from the numeric
  one of the same base name (`A` and `A$` are unrelated) and starts out empty
  (`""`). Up to **16** string variables. Strings are joined with `+`
  (`A$ + "!"`), and a value longer than 32 characters is truncated to 32.

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

**String expressions** use `+` to concatenate (`A$ + "!"`), and the same six
comparison operators compare two strings, character by character (a shorter
string sorts before a longer one with the same prefix) — yielding `1`/`0` just
like numeric comparisons, so they slot straight into `IF`:
`IF A$ = "Y" THEN ...`, `IF N$ < "M" THEN ...`.

### Functions

| Call | Returns |
|------|---------|
| `ABS(x)` | absolute value of `x` |
| `RND(n)` | a pseudo-random integer **1..n** (LCG; `RND(6)` is a die) |
| `POINT(x,y)` | the COLOUR at a screen pixel; 0 if off-screen |
| `PEEK(addr)` | the byte (0–255) at memory address `addr` |
| `LEN(s$)` | number of characters in the string `s$` |
| `ASC(s$)` | code (0–255) of the first character (0 if empty) |
| `CHR$(n)` | a one-character string with character code `n` |
| `LEFT$(s$,n)` | the first `n` characters of `s$` |
| `RIGHT$(s$,n)` | the last `n` characters of `s$` |
| `MID$(s$,i[,n])` | `n` characters of `s$` starting at position `i` (1-based); to the end if `n` is omitted |
| `STR$(x)` | the decimal text of number `x` (e.g. `STR$(-7)` is `"-7"`) |
| `VAL(s$)` | the number parsed from the start of `s$` (signed; stops at the first non-digit; `0` if none) |
| `EOF(n)` | `1` if the input data file is at end (or not open), else `0` (see *Data files*) |

`LEN`/`ASC`/`VAL`/`EOF` return numbers; `CHR$`/`LEFT$`/`RIGHT$`/`MID$`/`STR$`
return strings (their names end in `$`). `STR$` and `VAL` are inverses — the
number↔string conversion pair. Counts are clamped to what the source actually holds, so
`LEFT$("HI",9)` is just `"HI"`. `POKE addr,val` is a *statement* (below).

## Statements

A line may hold several statements separated by `:` —
`A=1 : B=2 : PRINT A+B`.

| Statement | Meaning |
|-----------|---------|
| `PRINT items` | print numbers/strings (see below); empty `PRINT` = blank line |
| `LET v = expr` | assign; the `LET` is optional, so `A=5` works too. Works for string variables too: `A$ = "HI"`, `N$ = F$ + L$` |
| `IF expr THEN ...` | if `expr` is non-zero, run the rest of the line; the `THEN` part may be a statement (`THEN PRINT X`) **or** a line number (`THEN 100`, an implicit `GOTO`) |
| `FOR v = a TO b [STEP s]` | begin a counting loop (`STEP` defaults to 1; negative start/limit OK) |
| `NEXT [v]` | end of loop body: add the step, loop back if still ≤ limit |
| `GOTO line` | jump to `line` |
| `GOSUB line` | call a subroutine; execution resumes after the `GOSUB` on `RETURN` |
| `RETURN` | return from the most recent `GOSUB` |
| `INPUT v` | print `? ` and read a value from the console into `v`; for a string variable (`INPUT A$`) the whole reply line becomes the string |
| `REM text` | comment; the rest of the line is ignored |
| `END` | stop the running program |
| `OPEN s$ [FOR] OUTPUT` / `OPEN s$ [FOR] INPUT` | open the data-file channel for writing / reading (see *Data files*) |
| `PRINT# expr` | write one value + newline as a record to the open output file |
| `INPUT# v` | read one record from the open input file into `v` (numeric or string) |
| `CLOSE` | close the data-file channel (commits an output file) |
| `COLOR c` / `COLOR r,g,b` | set the drawing colour: one PACKED RGB565 value, or three numbers (`r`,`b` 0–31, `g` 0–63) — see *Graphics* |
| `CLS` | clear the screen; the current `COLOR` is **not** changed |
| `PLOT x,y` | one pixel |
| `LINE x0,y0,x1,y1` | draw a line, both endpoints included |
| `BOX x0,y0,x1,y1[,FILL\|,NOFILL]` | rectangle — outline by default, solid with `FILL` |
| `CIRCLE x,y,r[,FILL\|,NOFILL]` | circle of radius `r` about `x,y` |
| `CIRCLE x,y,rx,ry[,FILL\|,NOFILL]` | **ellipse** — a second radius gives separate x and y radii |
| `RGB(r,g,b)` | *function*: pack a colour — `r`,`b` 0–31, `g` 0–63 |
| `IMAGE x,y,name$` | draw a P8I image file with its top-left at `x,y` |
| `GTEXT x,y,size,s$` | draw a string as graphics in the current `COLOR` |
| `GL s$` | send one raw graphics-language line as text — see *The graphics language* |
| `WINDOW` `VWPORT` `MOVE3` `DRAW3` `POLY3` `MDROTY` `CLBEG` `FLIP` … | the GL engine's verbs as native statements (51 of them) — see *The graphics language* |

### Graphics

Drawing goes to the display device. If none is fitted these statements print
`?No display` rather than quietly doing nothing.

> **Seeing it under the emulator.** There is no live window: press **Ctrl-\\** to
> render the screen to your terminal and keep going, or **Ctrl-C** to render it
> and quit. Run `p8xemu` with `-g out.ppm` as well and each of those also writes
> a real image file.

The screen is **480 × 272** in **RGB565 direct colour** — a pixel *is* its
colour, 0 is black; see *The screen* below for the colour model. `x` runs
0–479 left to right, `y` runs 0–271 top to bottom, and anything off-screen
is simply not drawn — it neither wraps nor errors.

```basic
10 COLOR 31,63,31               : REM white
20 BOX 0,0,479,271              : REM a border, outline
30 COLOR 0,63,0                 : REM green
40 LINE 0,0,479,271             : REM corner to corner
50 LINE 479,0,0,271
60 COLOR RGB(31,0,0)            : REM red, via the packing function
70 BOX 180,100,300,172,FILL     : REM a solid block
80 END
```

Any two opposite corners work for `BOX` — they are sorted for you, so
`BOX 150,86,90,50` draws the same rectangle.

**Ellipses.** A second radius turns `CIRCLE` into an ellipse — `rx` first, then
`ry`:

```basic
10 CIRCLE 240,136,80            : REM circle, radius 80
20 CIRCLE 240,136,180,60        : REM wide ellipse
30 CIRCLE 240,136,40,120,FILL   : REM tall, filled
```

The parser tells a second radius from the `FILL` modifier by looking at the
token: `FILL` and `NOFILL` are keywords, anything else begins an expression. That
is the second reason `NOFILL` had to be a real keyword rather than merely the
default — otherwise `CIRCLE x,y,r,NOFILL` would try to evaluate `NOFILL` as a
radius.

**Reading the screen back.** `POINT(x,y)` is a *function*, not a statement, and
returns the COLOUR at a pixel — 0 for anything off-screen — so a colour read
back compares exactly against the `RGB()` you drew with:

```basic
100 IF POINT(X,Y) = 0 THEN PLOT X,Y
```

**Text on the screen.** `GTEXT x,y,size,s$` draws a string as graphics, in the
current `COLOR`, with `x,y` the top-left corner:

```basic
10 COLOR 1
20 GTEXT 4,4,2,"P8X BASIC"      : REM double size
30 COLOR 2
40 GTEXT 4,26,1,"SCORE "+S$     : REM any string expression
```

`size` is a plain multiplier. The glyphs are 5×7 in a 6×8 cell, so size 1 gives
**80 columns and 34 rows**, size 2 gives 40 × 17, and so on. Only codes `$20`–`$5F`
have glyphs: lowercase is drawn as uppercase, and anything else comes out blank.
A string that runs off the right-hand edge simply stops — it does not wrap.

`GTEXT` is not a console: there is no cursor, no scrolling and no line wrap, and
it is the one drawing statement BASIC performs *itself* rather than handing to
the device (see below).

**The screen.** 480×272 in **RGB565 direct colour** — a pixel *is* its
colour, 65,536 of them, no palette and no modes. `RGB(r,g,b)` packs one:
five bits of red, six of green (the eye is fussiest there), five of blue.

```basic
10 COLOR 31,0,0 : BOX 0,0,479,271,FILL    : REM a red screen
20 COLOR 31,63,31                          : REM white
30 C=POINT(240,136) : COLOR C              : REM draw with a colour off the screen
```

`COLOR` takes either three numbers — `r,g,b` — or one *packed* colour: what
`RGB(r,g,b)` builds and `POINT(x,y)` returns. The comma decides, the same
way `CIRCLE`'s optional second radius does.

Arguments are masked to their fields. One wart, worn openly: BASIC's
integers are signed 16-bit, so a bright colour **prints** as a negative
number — `PRINT RGB(31,0,0)` says `-2048` — but stores and compares
bit-for-bit, so `IF POINT(x,y) = RGB(31,0,0)` works exactly.

`PALETTE` is gone with the palette: there is nothing to install a colour
into. Recolour-by-redraw is the trade stage 6 made for true colour.

**Images.** `IMAGE x,y,name$` draws a **P8I** file — the machine's own
picture format, ten self-describing header bytes (magic, version, geometry,
depth) and raw RGB565. The file knows its own size, so the statement cannot
be lied to about it; anything that is not P8I says `?NOT P8I`. Convert any
picture on the host with `tools/p8img.py photo.png` — it scales to fit the
screen and dithers to the 565 grid. Off-screen pixels are discarded, so an
image may hang off any edge. `IMAGE` borrows the data channel: a file
`OPEN`'d for `INPUT` is closed by it, like `SAVE` and `LOAD`.

**Colours.** There is no palette and no `PALETTE` statement (both retired
with direct colour, stage 6): the pen IS a colour. Set it either way —

```basic
10 COLOR 31,0,0                 : REM three numbers: r,b 0-31, g 0-63
20 COLOR RGB(0,63,0)            : REM or one packed value
30 C=POINT(10,10) : COLOR C     : REM ...including one read off the screen
```

Bright colours *print* as negative numbers (`PRINT RGB(31,0,0)` says
`-2048` — signed 16-bit ints), but store and compare bit-for-bit.

`NOFILL` exists so you can say it out loud; it is the default. It is a real
keyword rather than just an absence, because otherwise `NOFILL` would be read as
the word `NO` followed by the keyword `FILL` — and your outline would silently
come out solid.

**The device does the drawing, not BASIC.** `LINE` and `BOX` load a few hardware
registers and issue one command, so a filled box costs the same handful of
instructions as an empty one. That is why there is no speed penalty for `FILL`,
and why these statements are far faster than the equivalent `POKE` loop.

`GTEXT` is the exception, and deliberately so. The display has no text command,
and adding one would mean a font ROM and a glyph state machine in the FPGA, which
that build has no room for. So BASIC walks the glyph itself and issues one device
operation per lit pixel — fast enough for labels and titles, and it needs no
bitstream change at all, which is why `GTEXT` reached the board as nothing more
than a new `BASIC.BIN`.

Pen colours are chosen from 4096; the defaults are 0 black, 1 white, 2 red,
3 green. Every drawing command the device implements is now reachable from
BASIC; the one exception is its built-in self-test, which exists only in the
emulator (see [BACKLOG.md](../BACKLOG.md)) and can be triggered with `POKE` —
see the port table below.

### The graphics language (3D)

With a GL engine fitted (stage 10 — `man gl` on the machine documents the
device itself), the graphics language's verbs are **BASIC statements in
their own right**. Arguments are ordinary expressions, comma-separated,
the first one bare — so a rotation angle can be a variable, and a vertex
can be computed:

```basic
10 RESETF                       : REM power-up state (see below!)
20 CLEARS 0,0,0                 : REM both pages black (r,g,b)
30 WINDOW -120,120,-120,120     : REM 2D window -- x1,x2,y1,y2 order!
40 VWPORT 104,375,0,271         : REM where it lands on the screen
50 COLOR RGB(31,0,0)            : REM ONE pen statement, BOTH engines
60 PRMFIL 1                     : REM closed primitives fill
70 MDROTY A                     : REM compose a rotation, in degrees
80 POLY3 3,-80,-80,300,80,-80,300,0,40,420
90 FLIP
```

The full set, grouped the way `man gl` groups the device's verbs:

| Group | Statements |
|-------|------------|
| 2D | `MOVE` `MOVER` `DRAW` `DRAWR` `RECT` `RECTR` `POLY` `POLYR` `PRMFIL` `WINDOW` `VWPORT` `FLOOD` `CLEARS` |
| 3D | `MOVE3` `MOVER3` `DRAW3` `DRAWR3` `POINT3` `POLY3` `POLYR3` `CONVRT` |
| modeling matrix | `MDIDEN` `MDORG` `MDROTX` `MDROTY` `MDROTZ` `MDSCAL` `MDTRAN` `MDMATX` |
| viewing matrix | `VWIDEN` `VWRPT` `VWROTX` `VWROTY` `VWROTZ` `VWMATX` `DISTAN` `PROJCT` `DISTH` `DISTY` `CLIPH` `CLIPY` |
| command lists | `CLBEG` `CLEND` `CLRUN` `CLOOP` `CLDEL` `CLAPP` |
| pages & control | `FLIP` `PGSYNC` `WAIT` `RESETF` |

Parameters, units and order are exactly the device's — angles in degrees,
`WINDOW`/`VWPORT` in the PGC's `x1,x2,y1,y2` order, `FLOOD`/`CLEARS`
taking `r,g,b`. `POLY`/`POLY3` take a count and then that many vertices.
Three deliberate absences: `COLOR` (the ordinary `COLOR` statement now
sets the GL pen too, so one pen statement drives both drawing paths),
the GL `POINT` verb (`POINT()` the *function* owns the name — `GL "POINT"`
still reaches it), and `NOOP`.

**Recording.** Between `CLBEG n` and `CLEND` these statements *record*
into command list `n` instead of drawing, so a BASIC loop can build a
scene once and replay it — `CLOOP n,count` replays with matrix deltas
accumulating, which is how a stored scene spins with the CPU idle:

```basic
10 CLBEG 1 : MDROTY 5 : CLEND   : REM a list that nudges the world 5deg
20 CLOOP 1,7                    : REM 35 degrees, applied by the card
```

**Start with `RESETF`.** The machine draws its boot splash through this
same engine, and matrix verbs *compose* — without a reset, your first
rotation lands on top of whatever the splash (or the last program) left
behind.

**`GL s$` is the text escape hatch** for anything without a native
statement — short forms, the GL `POINT`, verbs newer than this guide:

```basic
50 GL "MDY "+STR$(A)
```

Mind the 32-character string limit: a GL line longer than that
truncates — a 9-coordinate `POLY3` does not fit in a string, which is
precisely why the native statements exist. Native statements also skip
the card's ASCII translator entirely (BASIC sends the binary opcode and
parameters), so they are faster and cannot mis-tokenize.

Native statements are **synchronous**: each one waits for the card to
finish before BASIC continues, so `POINT()` right after a draw reads
finished pixels — on silicon exactly as in the emulator. The price is
that a native `CLOOP` blocks until the whole replay ends; launch a
long fly-through with `GL "CLOOP 0 100"` instead — the text path does
not wait, and the card animates while BASIC runs on.

### Drawing modes — LINFUN (stage 10f)

`LINFUN m` picks how drawn pixels combine with what is already on the
screen: `0` replace (the default), `1` complement (invert the pixel
underneath — the pen is ignored), `2` OR, `3` AND, `4` XOR. It applies
to **lines, points and outlines from every drawing statement** — the
mode lives in the display device, so BASIC's own `LINE` and `PLOT`
honour it just like the GL verbs. Fills always replace.

XOR is the one to know: drawing the same thing twice removes it and
restores whatever was underneath, pixel-perfect — rubber-band cursors,
crosshairs, and erase-by-redraw animation without touching the scene:

```
10 LINFUN 4 : COLOR RGB(31,0,0)
20 FOR I=1 TO 20
30 LINE 50,100,430,200
40 LINE 50,100,430,200
50 NEXT I
60 LINFUN 0
```

The line strobes across the picture and everything under it survives.
`RESETF` (and a reboot) returns the mode to replace, so a scene that
begins with `RESETF` never inherits a stale mode.

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
`SAVE "NAME"` / `LOAD "NAME"` (persist the program to the CompactFlash
filesystem — ROM/disk builds; see *Editing a program* above),
`HELP` (print the supported statements, commands, functions, and operators),
and `BYE` (leave BASIC — returns to the monitor in the ROM/disk builds).

## Data files

Beyond `SAVE`/`LOAD` (which store the *program*), BASIC can read and write its own
**data files** on the CompactFlash card — one sequential channel at a time, in the
disk and run-from-OS builds (the standalone whole-ROM build has no card access).

```
10 OPEN "SCORES" FOR OUTPUT      write mode: creates/overwrites the file
20 FOR I=1 TO 3
30   PRINT# I*I                  each PRINT# writes ONE value as a record
40 NEXT
50 PRINT# "DONE"                 numbers and strings both work
60 CLOSE                         CLOSE commits the file

70 OPEN "SCORES" FOR INPUT       read mode
80 IF EOF(1) THEN 120            EOF(n) is 1 once the file is exhausted
90 INPUT# N : PRINT N            read until end — no count needed
100 GOTO 80
120 CLOSE
```

- The filename is any string expression (`OPEN F$ FOR INPUT`) and may be a
  **path** — a bare name is relative to the **current directory**, and a leading
  slash is absolute: `OPEN "/LOGS/A" FOR OUTPUT` writes into that subdirectory
  wherever you are (like `SAVE`/`LOAD` above; the leaf is up to 12 characters).
  Under P8X/OS that means `cd LOGS` then `OPEN "A" FOR OUTPUT` and
  `OPEN "/LOGS/A" FOR OUTPUT` are the same file. The files are visible to `DIR`
  and the host `p8xfs.py`. The `FOR` is optional.
- `PRINT#` writes exactly **one value per record** (its text form followed by a
  newline). `INPUT#` reads exactly **one record**: into a numeric variable it
  parses the decimal number, into a string variable (`INPUT# A$`) it takes the
  whole record text.
- One channel is open at a time. Opening a missing file `FOR INPUT` prints
  `?No file`. `EOF(n)` returns `1` once the input file is exhausted (and `1` if
  no file is open), so `IF EOF(1) THEN ...` cleanly ends a read loop; the channel
  number `n` is accepted but there is only one channel.

## Memory & hardware access

`PEEK`/`POKE` reach the full memory map (addresses in decimal):

| Address (dec / hex) | What |
|---------------------|------|
| 0–8191 / `$0000–$1FFF` | EEPROM (the interpreter ROM — read-only; 8 KB on rev-E hardware) |
| 8192–65279 / `$2000–$FEFF` | RAM, 56 KB (BASIC's program + variables live around `$8000`/`$A000`) |
| 65280 / `$FF00` | switch input port (`PEEK`) |
| 65282 / `$FF02` | LED output port (`POKE`) |
| 65284–65285 / `$FF04–05` | 6850 ACIA status / data |
| 65312–65327 / `$FF20–2F` | the graphics display (see below) |

So `POKE 65282, 170` lights an LED pattern, and `PRINT PEEK(65280)` reads the
switches.

The display's own registers are reachable too. The statements above now cover
every command the device implements, so this is for poking at the hardware
directly rather than for reaching anything you otherwise could not:

| Address | | Address | |
|---|---|---|---|
| 65312 | X0 | 65316 | pen |
| 65313 | Y0 | 65317 | **command** |
| 65314 | X1 | 65318 | status (bit 7 busy, bit 0 error) |
| 65315 | Y1 | 65319 | data — `POINT` result / `IDENT` stream |
| 65321–65324 | X0/Y0/X1/Y1 high bytes | 65320 | radius (x-radius for an ellipse) |
| 65325/65326 | `"P"`/`"G"` presence signature | 65327 | y-radius (ellipse) |

Write a coordinate's **low byte first** — the device clears the matching high
byte when the low one is written, so the other order loses it.

Commands: 1 plot, 2 line, 3 box, 4 box filled, 5 clear, 6 set palette, 7 circle,
8 circle filled, 9 point, 10 ellipse, 11 ellipse filled, 241 reset, 242 ident.
So a circle of radius 40 at the centre is:

```basic
10 POKE 65316,2 : POKE 65312,120 : POKE 65313,68
20 POKE 65320,40 : POKE 65317,7
```

Command 240 is a built-in self-test pattern, and it is **emulator-only** — the
FPGA rejects it and sets the error bit, so on real hardware it draws nothing.
Use the presence signature at 65325/65326 to tell a missing display from a
broken one. **Caution:** BASIC keeps its program and variables in low RAM
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
| `?SYNTAX ERROR IN 100` | the same, hit during `RUN` — names the failing line |
| `?UNDEF'D LINE` | `GOTO`/`GOSUB` to a line that doesn't exist |
| `?RETURN WITHOUT GOSUB` | `RETURN` with no matching `GOSUB` |

On any error the running program stops and returns to the prompt. A syntax error
raised while a program is running reports the line it happened on
(`?SYNTAX ERROR IN 100`); the bare form is used for mistakes typed at the prompt.

### Syntax checking at entry

Every line is checked for structural problems **the moment you enter it**, before
it is stored or run — so a typo is caught immediately, with the program left
unchanged, instead of only surfacing later at `RUN`. A line is rejected with
`?SYNTAX ERROR` (and *not* stored) if it has:

- **unbalanced parentheses** — `10 PRINT (1+2` or a stray `)`;
- an **unterminated string** — `20 PRINT "HI`;
- an **illegal statement start** — a line that begins with `THEN`, `TO`, `STEP`,
  or a function name (`ABS`/`RND`/`PEEK`), an operator, or a digit.

The check is deliberately *structural* only. It does **not** validate forward
references — `GOTO 100` before line 100 exists is legal and is still checked at
`RUN` (`?UNDEF'D LINE`) — and the tail of a `REM` is treated as free-form text,
so `10 REM (unbalanced "quotes` is accepted.

## Limits (current implementation)

- Numbers are integers only (16-bit signed); no floating point.
- Numeric variables: names ≤ 6 significant chars, up to 32; no arrays.
- String variables (`A$`): up to 16, each holding up to 32 characters; longer
  values are truncated. Not arrays. (`STR$`/`VAL` convert number↔string.)
- `FOR` loops nest **2 deep**; `GOSUB` nests **3 deep**.
- Data files: one channel open at a time, one value per record; `EOF(n)` tests
  for end of file — see *Data files*.
- No `DATA`/`READ`, `DIM`, `DEF FN`, `ON…GOTO`, or `WHILE`.
- Numbers are decimal only on input; `PRINT` shows signed decimal.

These reflect what `p8xbasic.asm` implements today; see [README](README.md) and
the project `BACKLOG.md` for what may come next.
