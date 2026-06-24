# os/commands/ — P8X/OS commands written in C

Userland commands for P8X/OS, written in C and compiled with
[`p8cc`](../../compiler/README.md) to loadable `/BIN/*.BIN` programs. They run
in the transient program area (`$B000`) under `RUN`, reach OS/BIOS services
through the `bios()`/`peek`/`poke`/`argstr()` builtins and the OS syscall table
(see [../README.md](../README.md)), and read/write the standard streams via
`getchar`/`putchar`/`puts` — so the shell can redirect (`<`/`>`) and pipe (`|`)
them like any program.

| Source | Command | Demonstrates |
|--------|---------|--------------|
| [`dir.c`](dir.c) | `DIR [-R] [path]` | `argstr()`, the `bios()` carry flag, `FOPENDIR`/`FNEXT`, `SYS_CWDLBA` (CWD); `-R` recurses the subtree (the FNEXT cursor is global BIOS state, so each level streams names while collecting child LBAs, then descends) |
| [`pwd.c`](pwd.c) | `PWD` | `SYS_GETCWD` ($4003) — the CWD via the syscall ABI, not OS internals |
| [`cat.c`](cat.c) | `cat` (stdin→stdout filter) | `getchar`/`putchar`, EOF (`-1`), input/output redirection, pipes |

Build one (or let [`../run.sh`](../run.sh) install all three into `/BIN`):

```sh
python3 compiler/p8cc.py os/commands/dir.c -o dir.asm
python3 assembler/p8xasm.py dir.asm -o dir.bin --base 0xB000
python3 tools/p8xfs.py put disk.img dir.bin --name /BIN/DIR.BIN --load 0xB000 --exec 0xB000
# on the P8X:   RUN /BIN/DIR.BIN /BIN
```

These double as the regression tests for the OS syscall + redirection + pipe
machinery (`emulator/test/c_dir_test.sh`, `c_dir_recursive_test.sh`,
`c_stdin_test.sh`, `c_pipe_test.sh`).
More commands to come (e.g. `MORE`/`WC`/`GREP`-style filters).
