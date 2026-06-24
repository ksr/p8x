# p8cc — C cross-compiler for the P8X

A tiny C compiler that runs on the host and emits P8X assembly for
[`assembler/p8xasm.py`](../assembler/p8xasm.py). Output targets the OS transient
program area (`$B000`), so a compiled program is a RUNnable `.BIN`.

```sh
python3 compiler/p8cc.py prog.c -o prog.asm
python3 assembler/p8xasm.py prog.asm -o prog.bin --base 0xB000
python3 tools/p8xfs.py put disk.img prog.bin --name /PROG.BIN --load 0xB000 --exec 0xB000
# then on the P8X:  RUN /PROG.BIN
```

A native (on-target) compiler is a later goal; this host cross-compiler comes
first and stays the primary tool.

## Two compilers: `p8cc.py` and `p8cc.c`

There are two implementations of the same compiler:

- **`p8cc.py`** — the original, written in Python. The everyday tool and the
  reference oracle. **It is the bootstrap and is never removed.**
- **`p8cc.c`** — the compiler rewritten in p8cc's *own* small-C subset
  (Milestone A, done). It is simultaneously valid standard C and valid
  p8cc-subset C, so it builds two ways:

  ```sh
  cc compiler/p8cc.c -o p8cc_host        # native bootstrap: ./p8cc_host < prog.c > prog.asm
  python3 compiler/p8cc.py compiler/p8cc.c -o p8cc.asm   # the self-compile proof
  ```

  It reads C from stdin and writes assembly to stdout (EOF is `0` from the P8X
  console or `-1` from host `getchar`). `p8cc.py` compiling `p8cc.c` cleanly is
  the proof that the subset is self-sufficient — "small C written in small C".
  Correctness is checked by a **differential** test
  (`emulator/test/c_selfhost_test.sh`): a sample compiled by *both* `p8cc.c` and
  `p8cc.py` runs to identical output on the P8X. (The two emit *behaviourally*
  equivalent asm — same program output — not byte-identical text; they differ in
  label names and argument-push order.)

  **As a day-to-day tool.** A `compiler/Makefile` builds the native compiler, and
  `compiler/p8cc-host` is a wrapper giving it `p8cc.py`'s file interface:

  ```sh
  make -C compiler                       # builds compiler/p8cc-host.bin (gitignored)
  compiler/p8cc-host prog.c -o prog.asm   # same interface as p8cc.py (auto-builds if stale)
  ```

  The native binary is a fast (~no startup) alternative to the Python tool and
  is literally the C codebase compiled for the host.

  **Milestone B** (run `p8cc.c` itself *on the P8X*) is a separate, open task: a
  full translation unit's working set exceeds the `$B000` TPA, so it needs the
  streaming/single-pass discipline the on-target assembler already uses — a RAM
  problem, not a language one. The language in `p8cc.c` is complete.

  `p8cc.c` is single-pass and so requires **declare-before-use** (function
  prototypes for mutual recursion, globals/structs before reference); `p8cc.py`
  is two-pass and more lenient. Both accept the same subset otherwise.

## Execution model

The P8X has no 16-bit accumulator, so expression results live in a **16-bit
pseudo-accumulator `AX`** (the memory word `__ax`). The hardware stack (`P3`)
holds expression temporaries (`PHA`/`PLA`) and call return addresses
(`JSR`/`RTS`). Binary operators compile to small **runtime helper calls**
(`__add`, `__sub`, `__mul`, `__eq`, `__lt`, `__not`) so the generated code stays
compact; only the helpers a program actually uses are emitted.

**Calling convention / frames.** A separate **software C-stack** (`__csp`, grows
down from `$F800`) holds call frames; `__fp` is the frame pointer. A caller
pushes arguments right-to-left, `JSR`s, then pops them; the callee (`__enter`)
saves the old `__fp`, sets `__fp = __csp`, and reserves space for locals, and
(`__leave`) unwinds on `return`. So **parameters live at `__fp+2, __fp+4, …`**
and **locals at `__fp-2, __fp-4, …`** — one frame per call, which makes functions
reentrant, so **recursion works**. Globals keep static storage. A program returns
to the OS shell with `RTS` (startup inits `__csp` then `JSR _f_main`).

## Supported subset

| area | supported |
|------|-----------|
| types | `int` (16-bit), `char` (8-bit), pointers `T *`, arrays `T a[N]`, `struct`/`union` (nestable) |
| top level | `struct`/`union` definitions, function definitions **with parameters**, global variable declarations |
| statements | `{ }`, declarations, `if`/`else`, `while`, `for (e; e; e)`, `return [e];`, `expr;`, `;` |
| operators | `=`  `\|\|` `&&`  `\|` `^` `&`  `==` `!=`  `<` `>` `<=` `>=`  `<<` `>>`  `+` `-` `*` `/` `%`  unary `-` `!` `~` `&` `*`  member `.` `->` |
| functions | parameters, **stack locals**, **recursion**, return value in `AX` |
| pointers | `&lvalue`, `*ptr` (load/store), pointer +/- scaled by element size, `a[i]` |
| primaries | int / char / string literals, identifiers, calls, `( )` |
| builtins | console: `getchar()` `putchar(e)` `puts(e)` (OS `SYS_GETC`/`SYS_PUTC`/`SYS_PUTS`); memory: `peek(addr)` `poke(addr,v)`; general: `bios(constaddr, p1, a)` |

**Library functions are written in C.** The console builtins are thin wrappers
over the **OS stream syscalls** (`$400C`/`$4009`/`$400F`), not the raw BIOS — so
a program's output is **redirectable by the shell**: `RUN PROG >FILE` streams its
`putchar`/`puts` to a file with no source change, and `RUN PROG <FILE` binds its
`getchar` to a file (which returns `-1` at end of file). Both combine —
`RUN CAT.BIN <IN >OUT` copies a file (see `os/commands/cat.c`). (A program
that iterates a directory while writing can't be redirected — the write stream
and directory iteration share the BIOS `SBUF`.)
Everything else a program needs (`strlen`, `getline`, `strcmp`, …) is ordinary C
compiled alongside it, now that pointers, arrays, and `char` work. See the
`strlen` in the test below for the pattern.

**Reaching the rest of the BIOS.** `peek(addr)`/`poke(addr, v)` do byte memory
access (e.g. the switch/LED ports at `$FF00`/`$FF02`), and `bios(addr, p1, a)`
calls *any* monitor routine: it sets `P1 = p1` and `A = a`, `JSR`s the (constant)
address, and returns the routine's `A` in the low byte **with the carry flag in
bit 8** (`result & 256`). So a status-returning call like `FNEXT` is usable from
C — `while ((bios(0x013C, 0, 0) & 256) == 0)` loops until end-of-directory. The
whole jump table is reachable: `bios(0x0112, str, 0)` is `puts` without the
newline, and the file API (`FOPEN`/`FGETB`/`FLOADAT`/…) is driven by `poke`-ing
its RAM ABI variables and `bios`-ing the call. (`bios`'s address must be a
literal — it becomes the `JSR` target.) `argstr()` returns the program's command
tail (the `RUN` argument in `P2`) as a `char *`. Both compilers support all of
these — see `os/commands/dir.c`, the OS `DIR` command written in C.

### `p8lib.c` — a C-source standard library

[`p8lib.c`](p8lib.c) is a small library written in the subset over those
builtins: `strlen`/`strcpy`/`strcmp`, `getline`/`putdec`, and **file** helpers
`loadfile(name, dest)` / `savefile(name, data, len)` (which drive
`FNORM`/`FFIND`/`FLOADAT` and `FWOPEN`/`FPUTB`/`FCLOSE`). There is no `#include`
or linker, so you use it by **prepending** it to your program:

```sh
cat compiler/p8lib.c prog.c > all.c
python3 compiler/p8cc.py all.c -o all.asm      # or: compiler/p8cc-host all.c -o all.asm
```

Caveats it documents: `bios()` doesn't surface the carry flag, so
`loadfile`/`savefile` don't detect a missing file or a full disk; and `loadfile`
reads **whole sectors**, so its destination must be sector-sized (≥ 512 bytes
for any file ≤ 512). Exercised end-to-end by `emulator/test/c_libfile_test.sh`
(a `savefile`→`loadfile` round-trip, differential across both compilers).

`int` is 16-bit (comparisons and `/` `%` are **unsigned** 16-bit); `char` is
8-bit. The compiler tracks types so a dereference loads/stores the right width
(int/pointer = 2 bytes, char = 1) and pointer arithmetic scales by element size.
Scalar locals/params occupy a 2-byte slot; arrays occupy `count * elemsize`.
String literals are pooled and evaluate to their address.

### Current limitations (next phases)

- `struct`/`union` are used **by pointer**: no by-value struct parameters,
  returns, or whole-struct assignment (assign individual members, or pass a
  pointer). Union members all share offset 0; no bitfields; no `sizeof()`
  operator yet. Members are laid out with no padding (byte-addressed machine).
- **Global initializers** are supported and must be compile-time constants:
  scalar int/char, a string for a `char *` or `char[]` (length inferable from
  `[]`), and brace lists for arrays — including string tables (`char *t[] =
  {"a","b"}`). Not yet: `&global` address constants, nested-aggregate braces,
  or initialized locals beyond a scalar expression.
- Function **return types are tracked** (a `T *`-returning call participates
  correctly in pointer arithmetic and dereference); a call to an undeclared
  function still defaults to `int`.
- `for`-init is an expression, not a declaration: locals are function-scoped, so
  declare the loop variable before the loop (`int i; for (i = 0; ...)`).
- Locals are function-scoped (no per-block shadowing); the C-stack and the
  hardware return stack are both in the TPA, so deep recursion is bounded by RAM.
  See the project backlog.

## Testing

`emulator/test/c_compile_test.sh` (`make test-c`) compiles a C program, assembles
it, RUNs it under P8X/OS, and checks the output: a `while` loop printing `12345`,
then **recursive `fact(5)`** → `FACT-OK`, a two-arg `add` → `ADD-OK`, and
`FOR-OK`/`LOG-OK`/`BIT-OK`/`SHIFT-OK` covering `for`, short-circuit `&&`/`||`,
bitwise `& | ^ ~`, and shifts `<< >>`.

`emulator/test/c_libc_test.sh` exercises **input**: a program reads a line with
`getchar()`, upper-cases it into a `char` buffer, `puts()` it, and prints its
length using a `strlen()` written in C — end-to-end proof that the I/O builtins
and C-source library functions work together.

`emulator/test/c_struct_test.sh` covers `struct`/`union`: a nested `struct Rect`
of `struct Point`s, `.`/`->` access, pointer-to-struct, an array member, and a
union — checking the rendered output `796A`.

`emulator/test/c_global_test.sh` covers global initializers: a scalar, a
`char *` string, an `int[]` list, a `char *[]` string table, and an inferred
`char[]` — output `7HI` / `6CY` / `YO`.

`emulator/test/c_selfhost_test.sh` is the Milestone-A check for `p8cc.c`: it
builds the host bootstrap with `cc`, confirms `p8cc.py` self-compiles `p8cc.c`,
and runs a feature-spanning sample compiled by *both* compilers, asserting
byte-identical P8X output (`12345678Y120AZ5QRSTG`).
