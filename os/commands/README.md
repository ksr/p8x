# os/commands/ — P8X/OS commands written in C

Userland commands for P8X/OS, written in C and compiled with
[`p8cc`](../../compiler/README.md) to loadable `/bin/*.bin` programs. They run
in the transient program area (`$7A00`) under `run`, reach OS/BIOS services
through the `bios()`/`peek`/`poke`/`argstr()` builtins and the OS syscall table
(see [../README.md](../README.md)), and read/write the standard streams via
`getchar`/`putchar`/`puts` — so the shell can redirect (`<`/`>`) and pipe (`|`)
them like any program.

## Running them

Once installed in `/bin`, a command runs by **bare name** — the shell's implicit
RUN searches `path` (default `/bin`) and appends `.bin`:

```
dir /bin            cat README.TXT          pwd
```

equivalently `run /bin/dir.bin /bin`, etc. Every command accepts **`-h`** to
print a one-line usage summary and exit.

> **Hand-assembled counterparts.** Each of these commands also has a hand-written
> P8X assembler version in [`../commands-asm/`](../commands-asm/README.md),
> verified byte-identical in behavior and ~2.3× smaller overall (up to 5.8×).
> `run.sh` installs them to a parallel `/bina`, so you can compare on-target:
> `run /bina/grep.bin …` vs `grep …`.

> **Drives.** A second CF is **mounted at `/d1`** in one unified namespace, so
> these commands are **drive-unaware**: an ordinary `/d1/...` path reaches drive 1
> with no special syntax — `cat /d1/NOTES`, `dir /d1/bin`, `dir /d1/*.C`,
> `grep x /d1/SRC/*.C`, and cross-mount `cp /d1/A /B` (the read and write streams
> each carry their own drive via `ROSDRV`/`WOSDRV`). The drive selection lives in
> one place — the `FRESOLVE`/`RV_START` mount redirect — not in any command, so
> even the stdin-filter tools (`grep`, `wc`, `head`, …) get the mount for free
> without growing. See [../README.md](../README.md) "Two drives".

> **Note — DIR, PWD, CAT, and TREE are no longer shell built-ins** (the
> minimal-kernel split): they were removed from the OS and run from `/bin` by
> bare name, so `dir -R`, `pwd`, `cat file`, `tree` all just work (and honour
> `-h`). The kernel keeps only what can't be a `/bin` program — `run`, the
> authoring/FS primitives (`save`/`dep`/`load`/`del`/`mkdir`/`rmdir`/`cd`), and
> `help`/`exit`/`pack`/`fsck`/`format`. **`dump` stays native** — as a `/bin`
> program it would load into the `$7A00` TPA and overwrite the very memory it
> dumps. Consequence: a freshly-`format`ted card (no `/bin`) can't `dir`/`cat`
> until `/bin` is repopulated (from the host, or a future master CF — backlog).

## Commands

| Source | Usage | What it does |
|--------|-------|--------------|
| [`dir.c`](dir.c) | `dir [-R] [path\|glob] [-h]` | List a directory (the path, or the CWD if omitted). Each line is a right-justified byte size, two spaces, then the name; directories show a blank size and a trailing `/`. `-R` recurses the whole subtree, indenting two spaces per level (the size column stays aligned). A last component with `*`/`?` is a case-insensitive **glob** (via `lib_glob`): `dir *.ASM`, `dir /bin/*.bin`, `dir -R *.C`. Streams one line at a time, so it redirects/pipes with no size limit. |
| [`pwd.c`](pwd.c) | `pwd [-h]` | Print the current working directory path. |
| [`cat.c`](cat.c) | `cat [file\|glob] [-h]` | Print a file, **or** copy stdin→stdout (the canonical filter) when given no file. So `cat file`, `cat <file`, and `cat \| …` all work. A last component with `*`/`?` is a case-insensitive **glob** (via `lib_globx`): `cat *.ASM` concatenates every matching file, and `cat *.ASM >ALL.TXT` captures them — directory iteration now coexists with an open write stream (see FSDIRBUF below). Reading the **console** (e.g. `cat >FILE`), each key echoes and **Ctrl-D** ends the input. |
| [`wc.c`](wc.c) | `wc [file\|glob] [-h]` | Count lines, words, and bytes → `L W B`. A file, a glob (`wc *.LOG` = combined count over all matches), `<file`, or a pipe. Counts are 16-bit. |
| [`grep.c`](grep.c) | `grep [-r] regex [file\|glob] [-h]` | Print lines matching a **basic regex** — `.` (any), `*`/`+`/`?` (zero-or-more / one-or-more / zero-or-one), `^`/`$` (anchors); else literal. Reads the named `file`/glob (like cat) or stdin if none: `grep "^al" foo.txt`, `… \| GREP "x.*y"`. **`-r`** recurses the CWD tree (depth-first, like `dir -R`/`find`) and searches file **contents**, printing each hit as `path:line` — `grep -r "x.*y"`. Lines capped at 255 chars; `-r` is capped at 36 files. |
| [`cp.c`](cp.c) | `cp [-r] src dst [-h]` | Copy a file (read stream → write stream), or with **`-r`** a whole directory tree — recursively, and across the `/d1` mount (`cp -r /d1/SRC /SRC`). A `*`/`?` **glob** source copies every match into the destination directory (`cp *.ASM /BAK`). `-r` collects each level's entries before descending (the FNEXT cursor is global) and makes destination dirs via the `SYS_MKDIR` syscall. Supersedes the old `IMPORT` built-in. |
| [`mv.c`](mv.c) | `mv src dst [-h]` | Move/rename a file = copy + delete source (P8XFS has no rename primitive). A `*`/`?` **glob** source moves every match into the destination directory (`mv *.TMP TRASH`). `mv X X` is refused. |
| [`head.c`](head.c) | `head [-N] [file] [-h]` | First N lines (default 10) of a file or stdin. |
| [`tail.c`](tail.c) | `tail [-N] [file] [-h]` | Last N lines (default 10, max 40) of a file or stdin, via a ring buffer. |
| [`more.c`](more.c) | `more [file] [-h]` | Page a file or stdin a screenful (23 lines) at a time: space=next page, Enter=one line, q=quit. Forward pager (not full `less`). |
| [`sort.c`](sort.c) | `sort [file] [-h]` | Sort lines ascending (file or stdin). In-memory: ≤128 lines of ≤79 chars. |
| [`uniq.c`](uniq.c) | `uniq [file] [-h]` | Collapse **adjacent** duplicate lines (pair with `sort`). |
| [`sed.c`](sed.c) | `sed s/re/new/[g] [file] [-h]` | `s///` substitution; the left side is a **basic regex** (`.` `*` `+` `?` `^` `$`, via `lib_regex` — same matcher as grep), replacement is literal. First match or all with `g`; the whole matched span is replaced. `*` is non-greedy. |
| [`find.c`](find.c) | `find pattern [-h]` | Recursively print CWD paths whose name matches `pattern`: a case-insensitive **glob** (`*`/`?`, via `lib_glob`) if it contains `*` or `?`, else a literal substring. So `find *.C`, `find TEST?.ASM`, and `find BIN` (substring) all work. |
| [`diff.c`](diff.c) | `diff f1 f2 [-h]` | Prefix/suffix-anchored line diff: `<` lines only in f1, `>` only in f2. ≤96 lines/file (≤79 chars). |
| [`touch.c`](touch.c) | `touch name [name...] [-h]` | Create each named file empty if missing; an existing file is left **untouched** (not truncated). No mtime yet (no RTC); no globbing (a pattern only ever matches existing files). |
| [`tree.c`](tree.c) | `tree [-h]` | Depth-first indented listing of the CWD tree (same recursion as `dir -R`). |
| [`vi.c`](vi.c) | `vi name [-h]` | Minimal modal **VT100 screen editor**. Reads keys raw (CONIN, no echo) and drives the cursor with ANSI escapes, so it needs a VT100-compatible terminal. `h j k l` move, `i`/`a`/`A`/`o` insert, `x` delete char, `dd` delete line, `0`/`$`/`G`, **`u` undo** (single-level), **`/`pat + `n`** search (literal, forward, wraps), `:w`/`:q`/`:wq`/`:q!`. Selective redraw (one line per edit, full only on scroll) keeps it usable at serial baud. Flat 110×80 line buffer. Complements the line-oriented [`EDIT`](../../apps/README.md) app. |
| [`man.c`](man.c) | `man name [-h]` | Print the manual page for a command: streams `/man/<name>` to stdout (a `cat` with a fixed `/man/` prefix, so it is CWD-independent). Works for both `/bin` commands and OS built-ins; an unknown name prints `no manual entry for NAME`. Pages are plain text authored in [`os/man/`](../man/) and installed to `/man` by `run.sh`. |
| [`dump.c`](dump.c) | `dump addr [-h]` | Hex-dump 256 bytes from hex `addr` (16 rows of hex + ASCII); a console key pages, `.` exits. Memory-only (`peek` + CONIN). Formerly an OS built-in — moved out of the kernel (it needs no shell/FS state). |
| [`dep.c`](dep.c) | `dep addr b b ... [-h]` | Deposit hex byte values into memory starting at hex `addr` (`poke`); quiet on success. The counterpart to `dump`. Formerly an OS built-in. Note both live in the TPA at `$7A00`, so don't `dep` over that region. |

### Implementation notes

- **dir.c** — `argstr()`, the `bios()` carry flag to end the `FOPENDIR`/`FNEXT`
  loop, `SYS_OPENCWD` ($4012) to open the CWD with its full **16-bit** LBA (so a
  CWD at LBA ≥ 256 lists correctly, not the truncated `SYS_CWDLBA` low byte), and
  `FSDIRBUF` ($0145) to move iteration off the shared `SBUF` so output can stream.
  `-R`: the `FNEXT` cursor is **global** BIOS state, so each level streams its
  entries while only recording child-directory LBAs (16-bit) into a small
  per-level array, then descends (poking the high byte into `LBA1`/`$7048` before
  `FOPENDIRAT`) — bounded memory, no whole-tree buffer.
- **pwd.c** — `SYS_GETCWD` ($4003): the CWD comes through the syscall ABI, not
  by peeking OS RAM.
- **wc.c / grep.c** — stdin filters that compose with `<`/`|`. wc counts are
  16-bit. grep also takes an optional **file argument** (opened like cat —
  absolute path + `FRESOLVE`/`FOPEN`, read buffer at `$FC00` — else stdin) and
  matches a basic regex via the classic tiny matcher
  (`matchhere`/`match`): a single self-recursive `matchhere` (the `c*` case is an
  inline loop, *not* a separate `matchstar`) — deliberately **no forward
  declaration / mutual recursion**, since the native `p8cc.c` bootstrap rejects a
  standalone prototype. See *Shared code* below. **`grep -r`** adds a recursive
  content search: it can't grep files *during* the directory walk because the
  `FNEXT` cursor is global BIOS state (the same reason `dir -R`/`find` record-then-
  descend), so it runs in two phases — phase 1 walks the CWD tree depth-first
  (FSDIRBUF page `$EA`) collecting every file's absolute path into `rfiles[]`
  (48 × 96), phase 2 `open_path`s each and greps it, prefixing hits with `path:`.
  The 48-file cap keeps grep's image low enough (ends ~`$E400` after the MOVW
  shrink) to leave ~11 levels of `collect()` recursion headroom under the `$F800`
  C-stack.
- **head.c / tail.c / more.c** — file-or-stdin via the shared `nextc()`/`openarg()`
  idiom (copied from cat/grep). `head` stops after N lines; `tail` keeps the last
  N in a flat ring buffer (`buf[slot*256+col]`, N≤40); `more` pages 23 lines then
  reads the continue key from the **console** (`CONIN`, BIOS $0100) — separate
  from the redirected stdin — so it pauses for both `more file` and `cmd | MORE`.
- **cp.c / mv.c** — copy SRC (read stream, buffer at `$FC00`) to DST (write
  stream). The read and write streams use **independent** buffers, so the
  byte loop interleaves them; but `FRESOLVE`/`FOPEN` and the write stream all
  transit `SBUF`, so DST is resolved *before* `FWOPEN` (which zeroes `SBUF`
  last). `mv` then `FDELETE`s the source; `mv X X` is guarded.
- **cat.c** — a filename argument is opened with `FRESOLVE` ($0133) +
  `FOPEN`/`FGETB` (read buffer `$FC00`). The BIOS resolves names from its own
  current directory (root for a fresh program), so cat builds an **absolute**
  path (CWD via `SYS_GETCWD`, unless the arg is already absolute) — `FRESOLVE`
  always starts at root, hence CWD-independent. With no argument it falls back
  to the stdin filter, so redirection and pipes are unchanged. A glob argument
  (`*`/`?`) is expanded by `lib_globx`'s `glob_expand` into a path list, then
  each path is streamed in turn (`cat *.ASM`). The hard part is `cat *.ASM
  >OUT`: a write stream is already open, and each file's `FRESOLVE` walks the
  directory through `SBUF` — which is also the write stream's buffer, so the
  naïve version overwrites each file's already-buffered output with directory
  data (`.   BBB`). Fix: cat points `FSDIRBUF` ($0145) at page `$FA`, and
  **FSCAN now honors that page too** (not just `FNEXT`; default `$71`=`SBUF`
  keeps every other caller byte-identical), so the per-file path walks read
  into `$FA00` and leave the write stream's `SBUF` intact. This is the general
  fix that lets any glob-expanding command redirect to a file — `cp`/`mv`'s
  *resolve-DST-before-FWOPEN* dance (above) only worked because they resolve a
  single target once.

## Building

Compile + assemble + install one (or let [`../run.sh`](../run.sh) install all
three into `/bin` on a fresh disk):

```sh
python3 compiler/p8cc.py os/commands/dir.c -o dir.asm
python3 assembler/p8xasm.py dir.asm -o dir.bin --base 0x7A00
python3 tools/p8xfs.py put disk.img dir.bin --name /bin/dir.bin --load 0x7A00 --exec 0x7A00
# on the P8X:   DIR /bin        (bare name via PATH)   or   RUN /bin/dir.bin /bin
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
| [`lib_stdin.c`](lib_stdin.c) | `path[80]`, `fromfile`, `nextc()` (next byte or 65535 at EOF), `openarg(a)` (open the optional file arg → 0 stdin / 1 opened / 2 not found). A `*`/`?` arg is expanded (via `lib_globx`) and `nextc()` reads all matches as **one concatenated stream**, so every command below gets globs for free (`grep x *.C`, `sort *.TXT`, `wc *.LOG`). | `grep`, `head`, `tail`, `more`, `sort`, `uniq`, `sed`, `wc` |
| [`lib_abspath.c`](lib_abspath.c) | `abspath(out, a)` — build an absolute path (CWD-prefixed when relative) into a caller buffer; returns chars consumed | `cp`, `mv`, `diff`, `touch` |
| [`lib_readline.c`](lib_readline.c) | `readline(buf)` — read one line via `nextc()` (CR dropped, LF-terminated); 1 = line, 0 = EOF. **Needs `//#use stdin` above it.** | `uniq`, `sed` |
| [`lib_streq.c`](lib_streq.c) | `streq(p, q)` — 1 if NUL-terminated strings are equal | `mv`, `uniq` |
| [`lib_glob.c`](lib_glob.c) | `gmatch(pat, name)` — case-insensitive whole-string glob match (`*`, `?`) | `dir`, `find`, `lib_globx` |
| [`lib_globx.c`](lib_globx.c) | `glob_expand(pat, out, maxn)` — expand a glob into a list of matching file paths (pulls in `lib_glob`) | `cat`, `cp`, `mv`, `lib_stdin` |
| [`lib_regex.c`](lib_regex.c) | `match(re, t)` / `matchhere(re, t)` — basic-regex matcher (`.` `*` `+` `?` `^` `$`); `matchhere` sets `rend` to the match end. (Character classes `[..]` / escapes don't fit in grep's host build yet — see BACKLOG.) | `grep`, `sed` |
| [`lib_dirent.c`](lib_dirent.c) | `de_read()` snapshots the entry `FNEXT` just matched into `de[17]`; `de_isfile()`/`de_isdir()`/`de_isdot()`/`de_len()`/`de_lba()` query it, `de_opendir(lba)` descends — all via the `SYS_DIRENTRY`/`SYS_OPENDIR` syscalls, so commands never hardcode BIOS scratch addresses | `dir`, `find`, `grep`, `tree`, `lib_globx` |

When a helper depends on another (e.g. `readline` calls `lib_stdin`'s `nextc()`),
list its `//#use` **after** the dependency's so `clib.py` splices them in the
right order (callee before caller).

Two rules for a helper meant to be lifted into a `lib_*.c`:

- keep it dependency-free (only the builtins / its own locals), and
- write it within the p8cc subset's intersection with the *native* `p8cc.c`.

**p8cc subset gotchas** (learned the hard way building these — keep helpers and
commands inside these limits, especially for `p8cc.c` parity):
- **No `++`/`--`** — write `i = i + 1`.
- **Watch for `*/` inside a block comment** — e.g. writing a regex example like
  `s/a*/x/` in a `/* ... */` comment ends the comment early (at the `a*/`) and
  spills the rest as code. Reword (no literal `*/`) or use `//` line comments.
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
  `$FC00` (~33 KB from the `$7A00` base). This bit `sed`/`diff` built with the
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

The core text/file utilities are all implemented (the table above). `dir` and
`find` match globs in place (via `lib_glob`); `cat` expands a glob into multiple
files (via `lib_globx`, e.g. `cat *.ASM >OUT`). Extending wildcards to the
remaining commands (`wc`/`grep`/`sort`/`cp`/`del`) is better done as a single
shell-level expansion pass (see the backlog) than per-command. Future ideas:
`TR`, `wc -l`-style flags, a real `LESS` (back-scroll).
