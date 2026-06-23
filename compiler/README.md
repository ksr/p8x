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
holds temporaries (`PHA`/`PLA`) and call return addresses (`JSR`/`RTS`). Binary
operators compile to small **runtime helper calls** (`__add`, `__sub`, `__mul`,
`__eq`, `__lt`, `__not`) so the generated code stays compact; only the helpers a
program actually uses are emitted. A program returns to the OS shell with `RTS`
(the startup stub is `JSR _f_main` / `RTS`).

## Supported subset (v0.1)

| area | supported |
|------|-----------|
| types | `int` (16-bit), `char` (8-bit) |
| top level | function definitions (no parameters yet), global variable declarations |
| statements | `{ }`, declarations, `if`/`else`, `while`, `return [e];`, `expr;`, `;` |
| operators | `=`  `==` `!=` `<` `>` `<=` `>=`  `+` `-`  `*`  unary `-` `!` |
| primaries | int / char / string literals, identifiers, calls, `( )` |
| builtins | `putchar(e)`, `puts(e)` (over the BIOS at `$0103` / `$0112`) |

`int` is 16-bit signed-ish (comparisons are currently **unsigned** 16-bit);
`char` is 8-bit. String literals are pooled and evaluate to their address.

### Current limitations (next phases)

- Every variable gets **static storage** — no stack frame, so **no recursion or
  reentrancy**, and user functions take **no arguments** yet. (Calling
  convention + stack locals is the next phase.)
- No pointers/arrays/`&`/`*`, no `/` `%` or shifts, no `for`, no `&&`/`||`
  short-circuit, no structs, no global initializers. See the project backlog.

## Testing

`emulator/test/c_compile_test.sh` (`make test-c`) compiles a C program, assembles
it, RUNs it under P8X/OS in the emulator, and checks the console output
(a `while` loop printing `12345`, then a user function + multiply printing
`SQ-OK`).
