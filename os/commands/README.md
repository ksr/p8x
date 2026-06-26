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

> **Note — DIR, PWD, CAT, and TREE are no longer shell built-ins** (the
> minimal-kernel split): they were removed from the OS and run from `/BIN` by
> bare name, so `DIR -R`, `PWD`, `CAT file`, `TREE` all just work (and honour
> `-h`). The kernel keeps only what can't be a `/BIN` program — `RUN`, the
> authoring/FS primitives (`SAVE`/`DEP`/`LOAD`/`DEL`/`MKDIR`/`RMDIR`/`CD`), and
> `HELP`/`EXIT`/`PACK`/`FSCK`/`FORMAT`. **`DUMP` stays native** — as a `/BIN`
> program it would load into the `$B000` TPA and overwrite the very memory it
> dumps. Consequence: a freshly-`FORMAT`ted card (no `/BIN`) can't `DIR`/`CAT`
> until `/BIN` is repopulated (from the host, or a future master CF — backlog).

## Commands

| Source | Usage | What it does |
|--------|-------|--------------|
| [`dir.c`](dir.c) | `DIR [-R] [path\|glob] [-h]` | List a directory (the path, or the CWD if omitted). `-R` recurses the whole subtree, indenting two spaces per level and flagging directories with a trailing `/`. A last component with `*`/`?` is a case-insensitive **glob** (via `lib_glob`): `DIR *.ASM`, `DIR /BIN/*.BIN`, `DIR -R *.C`. Streams names one at a time, so it redirects/pipes with no size limit. |
| [`pwd.c`](pwd.c) | `PWD [-h]` | Print the current working directory path. |
| [`cat.c`](cat.c) | `CAT [file] [-h]` | Print a file, **or** copy stdin→stdout (the canonical filter) when given no file. So `cat file`, `cat <file`, and `cat \| …` all work. Reading the **console** (e.g. `CAT >FILE`), each key echoes and **Ctrl-D** ends the input. |
| [`wc.c`](wc.c) | `WC [-h]` | Count lines, words, and bytes on stdin → `L W B`. A pure filter: `WC <file` or `… \| WC`. Counts are 16-bit. |
| [`grep.c`](grep.c) | `GREP regex [file] [-h]` | Print lines matching a **basic regex** — `.` (any), `*` (zero-or-more), `^`/`$` (anchors); else literal. Reads the named `file` (like cat) or stdin if none: `GREP "^al" foo.txt`, `… \| GREP "x.*y"`. Lines capped at 127 chars. |
| [`cp.c`](cp.c) | `CP src dst [-h]` | Copy a file (CWD-relative or absolute paths, across subdirectories). Read stream → write stream. |
| [`mv.c`](mv.c) | `MV src dst [-h]` | Move/rename a file = copy + delete source (P8XFS has no rename primitive). `MV X X` is refused. |
| [`head.c`](head.c) | `HEAD [-N] [file] [-h]` | First N lines (default 10) of a file or stdin. |
| [`tail.c`](tail.c) | `TAIL [-N] [file] [-h]` | Last N lines (default 10, max 20) of a file or stdin, via a ring buffer. |
| [`more.c`](more.c) | `MORE [file] [-h]` | Page a file or stdin a screenful (23 lines) at a time: space=next page, Enter=one line, q=quit. Forward pager (not full `less`). |
| [`sort.c`](sort.c) | `SORT [file] [-h]` | Sort lines ascending (file or stdin). In-memory: ≤96 lines of ≤63 chars. |
| [`uniq.c`](uniq.c) | `UNIQ [file] [-h]` | Collapse **adjacent** duplicate lines (pair with `SORT`). |
| [`sed.c`](sed.c) | `SED s/old/new/[g] [file] [-h]` | Literal `s///` substitution (first match, or all with `g`). No regex. |
| [`find.c`](find.c) | `FIND pattern [-h]` | Recursively print CWD paths whose name matches `pattern`: a case-insensitive **glob** (`*`/`?`, via `lib_glob`) if it contains `*` or `?`, else a literal substring. So `FIND *.C`, `FIND TEST?.ASM`, and `FIND BIN` (substring) all work. |
| [`diff.c`](diff.c) | `DIFF f1 f2 [-h]` | Prefix/suffix-anchored line diff: `<` lines only in f1, `>` only in f2. ≤40 lines/file. |
| [`tree.c`](tree.c) | `TREE [-h]` | Depth-first indented listing of the CWD tree (same recursion as `DIR -R`). |

### Implementation notes

- **dir.c** — `argstr()`, the `bios()` carry flag to end the `FOPENDIR`/`FNEXT`
  loop, `SYS_OPENCWD` ($4012) to open the CWD with its full **16-bit** LBA (so a
  CWD at LBA ≥ 256 lists correctly, not the truncated `SYS_CWDLBA` low byte), and
  `FSDIRBUF` ($0145) to move iteration off the shared `SBUF` so output can stream.
  `-R`: the `FNEXT` cursor is **global** BIOS state, so each level streams its
  entries while only recording child-directory LBAs (16-bit) into a small
  per-level array, then descends (poking the high byte into `LBA1`/`$9D48` before
  `FOPENDIRAT`) — bounded memory, no whole-tree buffer.
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
- **head.c / tail.c / more.c** — file-or-stdin via the shared `nextc()`/`openarg()`
  idiom (copied from cat/grep). `head` stops after N lines; `tail` keeps the last
  N in a flat ring buffer (`buf[slot*128+col]`, N≤20); `more` pages 23 lines then
  reads the continue key from the **console** (`CONIN`, BIOS $0100) — separate
  from the redirected stdin — so it pauses for both `MORE file` and `cmd | MORE`.
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

## Shared code (`//#use` + `lib_*.c`)

There is **no linker and no `#include`** in p8cc, so reusable helpers are shared
by **concatenation**: a command opts in with a directive line

```c
//#use stdin        // splices in os/commands/lib_stdin.c, ahead of this source
```

and the build step ([`tools/clib.py`](../../tools/clib.py)) replaces that line
with the contents of `os/commands/lib_<name>.c` *before* `p8cc` runs. A source
with no `//#use` passes through unchanged, so the build can run `clib.py` over
every command uniformly. The helper text is spliced **above** the command, so
its functions are defined before any caller — keeping the combined source inside
the native `p8cc.c` subset (no forward declarations). Both compilers see the same
combined source: `p8cc.py combined.c` or `p8cc_host < combined.c`.

`run.sh` and the `c_*_test.sh` harness both run `clib.py` first. To share a new
helper, drop it in `os/commands/lib_NAME.c` and add `//#use NAME` to each
consumer.

**Current libraries:**

| Library | Provides | Used by |
|---------|----------|---------|
| [`lib_stdin.c`](lib_stdin.c) | `path[80]`, `fromfile`, `nextc()` (next byte or 65535 at EOF), `openarg(a)` (open the optional file arg → 0 stdin / 1 opened / 2 not found) | `grep`, `head`, `tail`, `more`, `sort`, `uniq`, `sed` |
| [`lib_abspath.c`](lib_abspath.c) | `abspath(out, a)` — build an absolute path (CWD-prefixed when relative) into a caller buffer; returns chars consumed | `cp`, `mv`, `diff` |
| [`lib_readline.c`](lib_readline.c) | `readline(buf)` — read one line via `nextc()` (CR dropped, LF-terminated); 1 = line, 0 = EOF. **Needs `//#use stdin` above it.** | `uniq`, `sed` |
| [`lib_streq.c`](lib_streq.c) | `streq(p, q)` — 1 if NUL-terminated strings are equal | `mv`, `uniq` |
| [`lib_glob.c`](lib_glob.c) | `gmatch(pat, name)` — case-insensitive whole-string glob match (`*`, `?`) | `dir` |

When a helper depends on another (e.g. `readline` calls `lib_stdin`'s `nextc()`),
list its `//#use` **after** the dependency's so `clib.py` splices them in the
right order (callee before caller).

Two rules for a helper meant to be lifted into a `lib_*.c`:

- keep it dependency-free (only the builtins / its own locals), and
- write it within the p8cc subset's intersection with the *native* `p8cc.c`.

**p8cc subset gotchas** (learned the hard way building these — keep helpers and
commands inside these limits, especially for `p8cc.c` parity):
- **No `++`/`--`** — write `i = i + 1`.
- **No `break`/`continue`** (rejected by `p8cc.py`) — fold the exit into the loop
  condition, or use a flag.
- **No forward declarations / mutual recursion** (`p8cc.c` drops the rest of the
  file) — make functions self-recursive, define callees first.
- **`<`/`>` are UNSIGNED** — never return a negative sentinel and test `< 0`
  (it's always false); use a boolean comparator (e.g. `lless()` over masked
  bytes) instead of a `-1/0/1` `lcmp()`.
- **Avoid `int` arrays for indices** — they misbehaved as a sort permutation
  array; sort swaps the `char` slots in place instead. Prefer flat `char`
  buffers indexed by `slot*W+col`.
- **Don't pass `array + expr` as a pointer to a function** (e.g.
  `puts(buf + i*64)` printed the wrong slot) — index with `buf[i*64+j]` instead.
- Declarations go at the **top of each function** (and a `lib_*.c`'s globals go
  at its top, so they precede the command's own globals after splicing).
- **TPA size limit (not a compiler bug):** the shared file read buffer lives at
  `$FC00` (just under the stack), so a command's code+globals must stay below
  `$FC00` (~19 KB from the `$B000` base). This bit `sed`/`diff` built with the
  *native* `p8cc.c`, whose codegen is ~8% larger than `p8cc.py`'s: with the old
  `$E000` buffer they overran it and read file data into their own code. Moving
  the buffer to `$FC00` fixed it — both build on **both** compilers now. (Was
  long misfiled as a "`p8cc.c` file-arg miscompile".) `diff` is the largest at
  ~17.6 KB on `p8cc.c`, so keep an eye on headroom there.

## Tests

These double as regression tests for the OS syscall, redirection, and pipe
machinery: `emulator/test/c_dir_test.sh`, `c_dir_recursive_test.sh`,
`c_cat_test.sh`, `c_filters_test.sh` (wc/grep), `c_fileops_test.sh` (cp/mv),
`c_pager_test.sh` (head/tail/more), `c_stdin_test.sh`, `c_redirect_test.sh`,
`c_pipe_test.sh`, and the implicit-RUN/PATH path in `os_path_test.sh`.

The core text/file utilities are all implemented (the table above). `DIR` and
`FIND` take globs (via `lib_glob`); extending wildcards to the rest is better done
as shell-level expansion (see the backlog) than per-command. Future ideas: `TR`,
`WC -l`-style flags, a real `LESS` (back-scroll).
