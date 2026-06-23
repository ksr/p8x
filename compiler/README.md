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
| types | `int` (16-bit), `char` (8-bit), pointers `T *`, arrays `T a[N]` |
| top level | function definitions **with parameters**, global variable declarations |
| statements | `{ }`, declarations, `if`/`else`, `while`, `return [e];`, `expr;`, `;` |
| operators | `=`  `==` `!=` `<` `>` `<=` `>=`  `+` `-` `*` `/` `%`  unary `-` `!` `&` `*` |
| functions | parameters, **stack locals**, **recursion**, return value in `AX` |
| pointers | `&lvalue`, `*ptr` (load/store), pointer +/- scaled by element size, `a[i]` |
| primaries | int / char / string literals, identifiers, calls, `( )` |
| builtins | `getchar()`, `putchar(e)`, `puts(e)` (over the BIOS at `$0100` / `$0103` / `$0112`) |

**Library functions are written in C.** The only I/O builtins are the three
above — `getchar` (BIOS `CONIN`, returns the next console byte in `AX`),
`putchar`, and `puts`. Everything else a program needs (`strlen`, `getline`,
`strcmp`, …) is ordinary C compiled alongside it, now that pointers, arrays, and
`char` work. See the `strlen` in the test below for the pattern.

`int` is 16-bit (comparisons and `/` `%` are **unsigned** 16-bit); `char` is
8-bit. The compiler tracks types so a dereference loads/stores the right width
(int/pointer = 2 bytes, char = 1) and pointer arithmetic scales by element size.
Scalar locals/params occupy a 2-byte slot; arrays occupy `count * elemsize`.
String literals are pooled and evaluate to their address.

### Current limitations (next phases)

- No `for`, no `&&`/`||` short-circuit, no shifts/bitwise, no structs/unions, no
  global initializers, no multi-level type checking (e.g. function return types
  default to `int`).
- Locals are function-scoped (no per-block shadowing); the C-stack and the
  hardware return stack are both in the TPA, so deep recursion is bounded by RAM.
  See the project backlog.

## Testing

`emulator/test/c_compile_test.sh` (`make test-c`) compiles a C program, assembles
it, RUNs it under P8X/OS, and checks the output: a `while` loop printing `12345`,
then **recursive `fact(5)`** → `FACT-OK` and a two-arg `add` → `ADD-OK`.

`emulator/test/c_libc_test.sh` exercises **input**: a program reads a line with
`getchar()`, upper-cases it into a `char` buffer, `puts()` it, and prints its
length using a `strlen()` written in C — end-to-end proof that the I/O builtins
and C-source library functions work together.
