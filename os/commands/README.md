# os/commands/ — P8X/OS commands written in C

Userland commands for P8X/OS, written in C and compiled with
[`p8cc`](../../compiler/README.md) to loadable `/BIN/*.BIN` programs. They run
in the transient program area (`$B000`) under `RUN`, reach OS/BIOS services
through the `bios()`/`peek`/`poke`/`argstr()` builtins and the OS syscall table
(see [../README.md](../README.md)), and read/write the standard streams via
`getchar`/`putchar`/`puts` — so the shell can redirect (`<`/`>`) and pipe (`|`)
them like any program.

## Running them

Once installed in `/BIN`, a command runs by **bare name** — the shell's implicit
RUN searches `PATH` (default `/BIN`) and appends `.BIN`:

```
DIR /BIN            CAT README.TXT          PWD
```

equivalently `RUN /BIN/DIR.BIN /BIN`, etc. Every command accepts **`-h`** to
print a one-line usage summary and exit.

> **Note — DIR and PWD are also shell built-ins**, which take priority over the
> `/BIN` programs of the same name. So bare `DIR`/`PWD` run the built-in (which
> ignores `-h`/`-R`); to reach the richer C versions use the explicit path, e.g.
> `RUN /BIN/DIR.BIN -R /` or `RUN /BIN/DIR.BIN -h`. `CAT` is **not** a built-in
> (it was removed once `cat.c` became a superset), so `CAT …` always runs
> `/BIN/CAT.BIN`. Whether to drop the DIR/PWD built-ins too is tracked in the
> [backlog](../../BACKLOG.md) (they're the only way to list a disk with no
> `/BIN` installed, e.g. right after `FORMAT`).

## Commands

| Source | Usage | What it does |
|--------|-------|--------------|
| [`dir.c`](dir.c) | `DIR [-R] [path] [-h]` | List a directory (the path, or the CWD if omitted). `-R` recurses the whole subtree, indenting two spaces per level and flagging directories with a trailing `/`. Streams names one at a time, so it redirects/pipes with no size limit. |
| [`pwd.c`](pwd.c) | `PWD [-h]` | Print the current working directory path. |
| [`cat.c`](cat.c) | `CAT [file] [-h]` | Print a file, **or** copy stdin→stdout (the canonical filter) when given no file. So `cat file`, `cat <file`, and `cat \| …` all work. Reading the **console** (e.g. `CAT >FILE`), each key echoes and **Ctrl-D** ends the input. |
| [`wc.c`](wc.c) | `WC [-h]` | Count lines, words, and bytes on stdin → `L W B`. A pure filter: `WC <file` or `… \| WC`. Counts are 16-bit. |
| [`grep.c`](grep.c) | `GREP regex [file] [-h]` | Print lines matching a **basic regex** — `.` (any), `*` (zero-or-more), `^`/`$` (anchors); else literal. Reads the named `file` (like cat) or stdin if none: `GREP "^al" foo.txt`, `… \| GREP "x.*y"`. Lines capped at 127 chars. |
| [`cp.c`](cp.c) | `CP src dst [-h]` | Copy a file (CWD-relative or absolute paths, across subdirectories). Read stream → write stream. |
| [`mv.c`](mv.c) | `MV src dst [-h]` | Move/rename a file = copy + delete source (P8XFS has no rename primitive). `MV X X` is refused. |

### Implementation notes

- **dir.c** — `argstr()`, the `bios()` carry flag to end the `FOPENDIR`/`FNEXT`
  loop, `SYS_CWDLBA` ($4006) for the CWD, and `FSDIRBUF` ($0145) to move
  iteration off the shared `SBUF` so output can stream. `-R`: the `FNEXT` cursor
  is **global** BIOS state, so each level streams its entries while only
  recording child-directory LBAs into a small per-level array, then descends —
  bounded memory, no whole-tree buffer.
- **pwd.c** — `SYS_GETCWD` ($4003): the CWD comes through the syscall ABI, not
  by peeking OS RAM.
- **wc.c / grep.c** — stdin filters that compose with `<`/`|`. wc counts are
  16-bit. grep also takes an optional **file argument** (opened like cat —
  absolute path + `FRESOLVE`/`FOPEN`, read buffer at `$E000` — else stdin) and
  matches a basic regex via the classic tiny matcher
  (`matchhere`/`match`): a single self-recursive `matchhere` (the `c*` case is an
  inline loop, *not* a separate `matchstar`) — deliberately **no forward
  declaration / mutual recursion**, since the native `p8cc.c` bootstrap rejects a
  standalone prototype. See *Shared code* below.
- **cp.c / mv.c** — copy SRC (read stream, buffer at `$E000`) to DST (write
  stream). The read and write streams use **independent** buffers, so the
  byte loop interleaves them; but `FRESOLVE`/`FOPEN` and the write stream all
  transit `SBUF`, so DST is resolved *before* `FWOPEN` (which zeroes `SBUF`
  last). `mv` then `FDELETE`s the source; `MV X X` is guarded.
- **cat.c** — a filename argument is opened with `FRESOLVE` ($0133) +
  `FOPEN`/`FGETB`. The BIOS resolves names from its own current directory (root
  for a fresh program), so cat builds an **absolute** path (CWD via
  `SYS_GETCWD`, unless the arg is already absolute) — `FRESOLVE` always starts
  at root, hence CWD-independent. With no argument it falls back to the stdin
  filter, so redirection and pipes are unchanged.

## Building

Compile + assemble + install one (or let [`../run.sh`](../run.sh) install all
three into `/BIN` on a fresh disk):

```sh
python3 compiler/p8cc.py os/commands/dir.c -o dir.asm
python3 assembler/p8xasm.py dir.asm -o dir.bin --base 0xB000
python3 tools/p8xfs.py put disk.img dir.bin --name /BIN/DIR.BIN --load 0xB000 --exec 0xB000
# on the P8X:   DIR /BIN        (bare name via PATH)   or   RUN /BIN/DIR.BIN /BIN
```

Either compiler works: `p8cc.py` (the Python bootstrap) or the native
`p8cc.c` build (`cc -O2 compiler/p8cc.c -o p8cc-host`) — they emit behaviorally
equivalent P8X assembly.

## Shared code

There is **no linker and no `#include`** — each command is one self-contained
translation unit. So a reusable helper (e.g. the basic-regex `match()` in
`grep.c`, which other tools will want) is shared by **copying the function block
verbatim** into each command, not by linking. Two practical rules for a helper
meant to be lifted:

- keep it dependency-free (only the builtins / its own locals), and
- write it within the p8cc subset's intersection with the *native* `p8cc.c`
  — in particular **no forward declarations / mutual recursion** (p8cc.c rejects
  a standalone prototype), declarations at the top of each function, and no
  `++`/`--`.

If a third consumer appears it'll be worth a real fix: a tiny build step that
concatenates a shared `lib*.c` ahead of the command source before compiling
(tracked in the backlog).

## Tests

These double as regression tests for the OS syscall, redirection, and pipe
machinery: `emulator/test/c_dir_test.sh`, `c_dir_recursive_test.sh`,
`c_cat_test.sh`, `c_filters_test.sh` (wc/grep), `c_fileops_test.sh` (cp/mv),
`c_stdin_test.sh`, `c_redirect_test.sh`, `c_pipe_test.sh`, and the
implicit-RUN/PATH path in `os_path_test.sh`.

More commands to come (e.g. `MORE`/`HEAD`/`TAIL`-style filters).
