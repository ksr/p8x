# os/commands/ — P8X/OS commands written in C

Userland commands for P8X/OS, written in C and compiled with
[`p8cc`](../../compiler/README.md) to loadable `/bin/*.bin` programs. They run
in the transient program area (`$6A00`) under `run`, reach OS/BIOS services
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

> **Sources on-card.** `run.sh` also ships the command *sources* under
> `/src/commands/c` (the command `.c` files — the shared `lib_*.c` helpers are
> **not** duplicated here; they live only in `/lib`, where the native `cc`'s
> `//#use` opens them as `/lib/lib_<name>.c`) and
> `/src/commands/asm` (the hand-assembled command `.asm` + the toolchain app
> sources `p8xcc.asm`/`p8xasm.asm`/`p8xedit.asm`; the shared includes are **not**
> here — like the C libs they live only in `/lib`, as `glob/globx/regex/stdin/
> distab/gfx.inc`, where the on-target `asm`'s `;#use` opens them). So you can
> read — and, for C, `cc /src/commands/c/pwd.c >pwd.asm` — any command right on
> the machine. The deprecated `cpp/lex/cc1` front end is **not** shipped (no
> binary, no man page, no source), matching its deprecation everywhere else.
>
> **Rebuild on-card.** Alongside the sources, `run.sh` lays down build-output
> dirs `/src/commands/c/bin` and `/src/commands/asm/bin`, and a real `Makefile`
> in each source dir. The OS **`make`** built-in reads the CWD `Makefile`
> (`target: deps` + TAB recipe), resolves prerequisites depth-first, and drives
> `cc`/`asm`: `cd /src/commands/c && make pwd` rebuilds one command, `make all`
> the whole dir, `make install` publishes to `/bin`, `make clean` wipes `bin/`
> — always-rebuild (P8XFS has no mtimes yet). See *Building on-target* below.

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
> program it would load into the `$6A00` TPA and overwrite the very memory it
> dumps. Consequence: a freshly-`format`ted card (no `/bin`) can't `dir`/`cat`
> until `/bin` is repopulated (from the host, or a future master CF — backlog).

## Commands

| Source | Usage | What it does |
|--------|-------|--------------|
| [`dir.c`](dir.c) | `dir [-R] [-S] [path\|glob] [-h]` | List a directory (the path, or the CWD if omitted). Each line is a right-justified byte size, two spaces, then the name; directories show a blank size and a trailing `/`. Entries are **sorted within each directory** (and per level under `-R`): by name (raw ASCII, so `A`-`Z` before `a`-`z`) by default, or by size largest-first with `-S` (ties by name; a dir has no size so counts as 0, sorting after files). `-R` recurses the whole subtree, indenting two spaces per level (the size column stays aligned). A last component with `*`/`?` is a case-insensitive **glob** (via `lib_glob`): `dir *.ASM`, `dir /bin/*.bin`, `dir -R *.C`. Buffers a directory's entries (single global set reused per level) to sort, then streams them. |
| [`pwd.c`](pwd.c) | `pwd [-h]` | Print the current working directory path. |
| [`cat.c`](cat.c) | `cat [file\|glob] [-h]` | Print a file, **or** copy stdin→stdout (the canonical filter) when given no file. So `cat file`, `cat <file`, and `cat \| …` all work. A last component with `*`/`?` is a case-insensitive **glob** (via `lib_globx`): `cat *.ASM` concatenates every matching file, and `cat *.ASM >ALL.TXT` captures them — directory iteration now coexists with an open write stream (see FSDIRBUF below). Reading the **console** (e.g. `cat >FILE`), each key echoes and **Ctrl-D** ends the input. |
| [`wc.c`](wc.c) | `wc [file\|glob] [-h]` | Count lines, words, and bytes → `L W B`. A file, a glob (`wc *.LOG` = combined count over all matches), `<file`, or a pipe. Counts are 24-bit (files may be up to 16 MB), printed via a byte-wise divmod10. |
| [`grep.c`](grep.c) | `grep [-r] regex [file\|glob] [-h]` | Print lines matching a **basic regex** — `.` (any), `*`/`+`/`?` (zero-or-more / one-or-more / zero-or-one), `^`/`$` (anchors); else literal. Reads the named `file`/glob (like cat) or stdin if none: `grep "^al" foo.txt`, `… \| GREP "x.*y"`. **`-r`** recurses the CWD tree (depth-first, like `dir -R`/`find`) and searches file **contents**, printing each hit as `path:line` — `grep -r "x.*y"`. Lines capped at 255 chars; `-r` is capped at 36 files. |
| [`cp.c`](cp.c) | `cp [-r] src dst [-h]` | Copy a file (read stream → write stream), or with **`-r`** a whole directory tree — recursively, and across the `/d1` mount (`cp -r /d1/SRC /SRC`). A `*`/`?` **glob** source copies every match into the destination directory (`cp *.ASM /BAK`). `-r` collects each level's entries before descending (the FNEXT cursor is global) and makes destination dirs via the `SYS_MKDIR` syscall. Supersedes the old `IMPORT` built-in. |
| [`mv.c`](mv.c) | `mv src dst [-h]` | Move/rename a file = copy + delete source (P8XFS has no rename primitive). A `*`/`?` **glob** source moves every match into the destination directory (`mv *.TMP TRASH`). `mv X X` is refused. |
| [`head.c`](head.c) | `head [-N] [file] [-h]` | First N lines (default 10) of a file or stdin. |
| [`tail.c`](tail.c) | `tail [-N] [file] [-h]` | Last N lines (default 10, max 40) of a file or stdin, via a ring buffer. |
| [`more.c`](more.c) | `more [file] [-h]` | Page a file or stdin a screenful (23 lines) at a time: space=next page, Enter=one line, q=quit. Forward pager (not full `less`). |
| [`sort.c`](sort.c) | `sort [file] [-h]` | Sort lines ascending (file or stdin). In-memory: ≤128 lines of ≤79 chars. |
| [`uniq.c`](uniq.c) | `uniq [file] [-h]` | Collapse **adjacent** duplicate lines (pair with `sort`). |
| [`sed.c`](sed.c) | `sed s/re/new/[g] [file] [-h]` | `s///` substitution; the left side is a **basic regex** (`.` `*` `+` `?` `^` `$`, via `lib_regex` — same matcher as grep), replacement is literal. First match or all with `g`; the whole matched span is replaced. `*` is non-greedy. |
| [`awk.c`](awk.c) | `awk [-F c] 'program' [file]` | Small awk: records split into fields on whitespace (or `-F c`); one rule `[/regex/] { print items }` — `/regex/` (via `lib_regex`) or empty = every line, a bare pattern prints the line. `print` items: `$0`/`$N`/`$NF`/`NF`/`NR`/`"str"`, comma = a space between. File arg or stdin (pipes). The program is one quoted arg (awk strips the quotes). Hand-asm twin [`../commands-asm/awk.asm`](../commands-asm/awk.asm) (verified identical output). No BEGIN/END/printf/expr yet. |
| [`find.c`](find.c) | `find pattern [-h]` | Recursively print CWD paths whose name matches `pattern`: a case-insensitive **glob** (`*`/`?`, via `lib_glob`) if it contains `*` or `?`, else a literal substring. So `find *.C`, `find TEST?.ASM`, and `find BIN` (substring) all work. |
| [`diff.c`](diff.c) | `diff f1 f2 [-h]` | Prefix/suffix-anchored line diff: `<` lines only in f1, `>` only in f2. ≤96 lines/file (≤79 chars). |
| [`touch.c`](touch.c) | `touch name [name...] [-h]` | Create each named file empty if missing; an existing file is left **untouched** (not truncated). No mtime yet (no RTC); no globbing (a pattern only ever matches existing files). |
| [`tree.c`](tree.c) | `tree [-h]` | Depth-first indented listing of the CWD tree (same recursion as `dir -R`). |
| [`vi.c`](vi.c) | `vi name [-h]` | Minimal modal **VT100 screen editor**. Reads keys raw (CONIN, no echo) and drives the cursor with ANSI escapes, so it needs a VT100-compatible terminal. `h j k l` move, `i`/`a`/`A`/`o` insert, `x` delete char, `dd` delete line, `0`/`$`/`G`, **`u` undo** (single-level), **`/`pat + `n`** search (literal, forward, wraps), `:w`/`:q`/`:wq`/`:q!`. Selective redraw (one line per edit, full only on scroll) keeps it usable at serial baud. Flat 110×80 line buffer. Complements the line-oriented [`EDIT`](../../apps/README.md) app. |
| [`man.c`](man.c) | `man name [-h]` | Print the manual page for a command: streams `/man/<name>` to stdout (a `cat` with a fixed `/man/` prefix, so it is CWD-independent). Works for both `/bin` commands and OS built-ins; an unknown name prints `no manual entry for NAME`. Pages are plain text authored in [`os/man/`](../man/) and installed to `/man` by `run.sh`. |
| [`dump.c`](dump.c) | `dump addr [-h]` | Hex-dump 256 bytes from hex `addr` (16 rows of hex + ASCII); a console key pages, `.` exits. Memory-only (`peek` + CONIN). Formerly an OS built-in — moved out of the kernel (it needs no shell/FS state). |
| [`dep.c`](dep.c) | `dep addr b b ... [-h]` | Deposit hex byte values into memory starting at hex `addr` (`poke`); quiet on success. The counterpart to `dump`. Formerly an OS built-in. Note both live in the TPA at `$6A00`, so don't `dep` over that region. |
| [`cmp.c`](cmp.c) | `cmp file1 file2 [-h]` | Byte-for-byte file compare — silent if identical, else `cmp: files differ: byte N, line M`, or `cmp: EOF on fileX` when one is a prefix. Reads file1 into an 8 KB buffer, streams file2 (both via the single BIOS read stream, like diff). Hand-asm twin [`../commands-asm/cmp.asm`](../commands-asm/cmp.asm) (identical output). The byte-level companion to diff. |
| [`examine.c`](examine.c) | `examine addr [-h]` | Interactive examine/modify from hex `addr` (`peek`/`poke`) — the shell counterpart of the monitor's `E`: shows `aaaa: vv`, then Enter advances, two hex digits write + advance, `.` quits. Console input via `getchar` (`SYS_GETC`). Runs in the `$6A00` TPA, so don't examine over that region. |
| [`disasm.c`](disasm.c) | `disasm start end [-h]` | Disassemble the hex range `[start,end)` — one instruction per line (`AAAA: bb bb.. MNEMONIC operand`), unknown bytes print `???`. Memory-only (`peek`). The opcode table [`lib_distab.c`](lib_distab.c) is **generated** from `genucode.OPC` by [`generators/gen_p8xdis.py`](../../generators/gen_p8xdis.py) (spliced via `//#use distab`), so it never drifts from the ISA. Runs in the `$6A00` TPA, so don't disassemble that range. C-only (no hand-asm twin yet). |
| [`cube.c`](cube.c) | `cube [frames]` | Spinning perspective **wireframe cube** — the 3D demo and first client of `lib_g3d` (`//#use gfx` + `//#use g3d`). 64 frames (one full turn) by default. With the stage-8b geometry engine it uploads the static cube once and renders per frame with a matrix write (~3 ms of CPU, vsync-paced page flip, tear-free); `cube N s` forces the stage-7 software path (~72 ms/frame), which is also the automatic fallback without an engine. Rebuilt from constants each frame so it never accumulates rounding error. Needs the display (`?No display` without). C-only, and (like `disasm`) outside the `p8cc.c` self-host subset: its sine/edge tables are brace-initialized arrays. |

### Implementation notes

- **dir.c** — `argstr()`, the `bios()` carry flag to end the `FOPENDIR`/`FNEXT`
  loop, `SYS_OPENCWD` ($2012) to open the CWD with its full **16-bit** LBA (so a
  CWD at LBA ≥ 256 lists correctly, not the truncated `SYS_CWDLBA` low byte), and
  `FSDIRBUF` ($0145) to move iteration off the shared `SBUF` so output can stream.
  `-R`: the `FNEXT` cursor is **global** BIOS state, so each level streams its
  entries while only recording child-directory LBAs (16-bit) into a small
  per-level array, then descends (poking the high byte into `LBA1`/`$7048` before
  `FOPENDIRAT`) — bounded memory, no whole-tree buffer.
- **pwd.c** — `SYS_GETCWD` ($2003): the CWD comes through the syscall ABI, not
  by peeking OS RAM.
- **wc.c / grep.c** — stdin filters that compose with `<`/`|`. wc counts are
  24-bit (byte-wise divmod10, like dir's size column). grep also takes an optional **file argument** (opened like cat —
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

## Building on-target

You can rebuild any command **on the P8X itself**, from the sources shipped
under `/src`. Each source dir carries a real `Makefile` (`target: deps` + TAB
recipe, with `all`/`clean`/`install` targets); the **`make`** built-in reads the
CWD `Makefile`, resolves prerequisites depth-first (shared deps built once), and
runs the recipes through the toolchain (always rebuilds; no timestamps yet):

```
cd /src/commands/c
make pwd        rebuild one command   -> bin/pwd.bin  (cc then asm)
make all        rebuild every command -> bin/*.bin
make install    publish this dir's bin/*.bin over /bin
make clean      delete this dir's build outputs
```

The `/src/commands/asm` dir has the same targets (each recipe is a single `asm`
of the hand-asm twin), and `/src/os-bios` builds the monitor + OS. Recipes run
in the invoking CWD, so paths are dir-relative. A C command compiles then
assembles; a hand-asm command assembles directly (with `;#use` includes pulled
from `/lib`):

```
cc pwd.c >T.ASM              # cc writes T.ASM in the CWD (via the > redirect)
asm T.ASM bin/pwd.bin        # asm reads that relative T.ASM, writes the binary
asm pwd.asm bin/pwd.bin      # (asm dir: assemble the hand-asm twin directly)
```

So the loop is: edit a source under `/src/commands/{c,asm}` (with `edit`/`vi`),
`cd` into that dir, `make <name>`, and the fresh binary lands in `bin/`. To put
it on `PATH`, `make install` (or `cp` it to `/bin`).

## Building (host)

Compile + assemble + install one (or let [`../run.sh`](../run.sh) install all
three into `/bin` on a fresh disk):

```sh
python3 compiler/p8cc.py os/commands/dir.c -o dir.asm
python3 assembler/p8xasm.py dir.asm -o dir.bin --base 0x6A00
python3 tools/p8xfs.py put disk.img dir.bin --name /bin/dir.bin --load 0x6A00 --exec 0x6A00
# on the P8X:   DIR /bin        (bare name via PATH)   or   RUN /bin/dir.bin /bin
```

Either compiler works: `p8cc.py` (the Python bootstrap) or the native
`p8cc.c` build (`cc -O2 compiler/p8cc.c -o p8cc-host`) — they emit behaviorally
equivalent P8X assembly.

## Shared code (`//#use` + `lib_*.c`)

> **On-target too.** The native `cc` (`apps/p8xcc.asm`) now performs the same
> `//#use` splicing *on the P8X* — its recursive preprocessor opens
> `/lib/lib_NAME.c` (the `lib_*.c` sources, shipped to `/lib` by `run.sh`). So
> the earlier `cpp | lex | cc1` front end (which ran only the front half
> on-target) was **retired** (2026-07-14); `cc` compiles the whole thing on the machine.

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
| [`lib_apath.c`](lib_apath.c) | `abspath(out, a)` — build an absolute path (CWD-prefixed when relative) into a caller buffer; returns chars consumed. Spliced with `//#use apath`. | `cp`, `mv`, `diff`, `touch` |
| [`lib_rdline.c`](lib_rdline.c) | `readline(buf)` — read one line via `nextc()` (CR dropped, LF-terminated); 1 = line, 0 = EOF. Spliced with `//#use rdline`; **needs `//#use stdin` above it.** | `uniq`, `sed` |
| [`lib_streq.c`](lib_streq.c) | `streq(p, q)` — 1 if NUL-terminated strings are equal | `mv`, `uniq` |
| [`lib_glob.c`](lib_glob.c) | `gmatch(pat, name)` — case-insensitive whole-string glob match (`*`, `?`) | `dir`, `find`, `lib_globx` |
| [`lib_globx.c`](lib_globx.c) | `glob_expand(pat, out, maxn)` — expand a glob into a list of matching file paths (pulls in `lib_glob`) | `cat`, `cp`, `mv`, `lib_stdin` |
| [`lib_regex.c`](lib_regex.c) | `match(re, t)` / `matchhere(re, t)` — basic-regex matcher (`.` `*` `+` `?` `^` `$`); `matchhere` sets `rend` to the match end. (Character classes `[..]` / escapes don't fit in grep's host build yet — see BACKLOG.) | `grep`, `sed` |
| [`lib_dirent.c`](lib_dirent.c) | `de_read()` snapshots the entry `FNEXT` just matched into `de[18]` ([17] = the 24-bit length's high byte); `de_isfile()`/`de_isdir()`/`de_isdot()`/`de_len()`/`de_lba()` query it, `de_opendir(lba)` descends — all via the `SYS_DIRENTRY`/`SYS_OPENDIR` syscalls, so commands never hardcode BIOS scratch addresses | `dir`, `find`, `grep`, `tree`, `lib_globx` |
| [`lib_gfx.c`](lib_gfx.c) | C veneer over the **display device** ($FF20-$FF2F, via `peek`/`poke`): `gpresent` (probe first — an absent display floats the bus), `grgb`/`gcolor` (RGB565 pen), `gcls`, `gplot`, `gline`, `gbox(f)`, `gcircle(f)`, `gellipse(f)`, `gpoint`. Handles the 16-bit register pairs (low write clears high, highs at +9) and the GSTAT busy-wait, so every call is safe back to back. Asm twin: [`../commands-asm/lib_gfx.inc`](../commands-asm/lib_gfx.inc) (equates). | `cube`, `lib_g3d` |
| [`lib_g3d.c`](lib_g3d.c) | **Wireframe 3D** (STAGE7-DESIGN.md): retained edge pool (`g3line`, 512 edges), `g3window`/`g3view` (window-space clipping makes viewports true clip rectangles), `g3persp`, `g3render` (near clip → project → Cohen-Sutherland → viewport map → hardware LINE). Foundation: `muldiv(a,b,c)` — signed (a\*b)/c through a 32-bit intermediate; it probes for the **MDU** (the stage-8a hardware muldiv at `$FF30`, bit-exact to the same contract) and routes through it when fitted, else a native-`*`/`/` fast path when the product fits 16 bits, else the all-C 32-bit path. With the stage-8b **geometry engine** fitted, `g3render` auto-routes the whole pipeline into fabric (identical pixels), and the pro path — `g3up`/`g3mat`/`g3flags`/`g3go`/`g3flip`/`g3sync` — uploads a static model once and re-renders per frame with only a matrix write, page-flipped (`man g3d` on-target). Needs `//#use gfx` above it. | `cube` |
| [`lib_abi.c`](lib_abi.c) | **object-like `#define`s** naming the BIOS jump table + OS syscalls (`FOPEN`, `FGETB`, `FRESOLVE`, `SYS_GETCWD`, `SYS_MKDIR`, …) and the shared read buffer (`RDBUF` = `$FC00`), so a command writes `bios(FOPEN, RDBUF, 0)` not `bios(0x0124, 0xFC00, 0)`. `#define` is a compile-time substitution, so the code is **byte-identical** to the raw-hex form (no wrapper cost). Each address lives here alone; the asm twins use the parallel equates in [`../commands-asm/lib_abi.inc`](../commands-asm/lib_abi.inc). | any command that calls the FS/console directly (`cat`, `cp`, `dir`, `mv`, `vi`, `find`, `grep`, `tree`, `touch`, `pwd`, `diff`, `man`, `more`, `dump`, `lib_stdin`, `lib_apath`, `lib_dirent`, `lib_globx`) |

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
  `$FC00` (~37.9 KB from the `$6A00` base). This bit `sed`/`diff` built with the
  *native* `p8cc.c`, whose codegen is larger than `p8cc.py`'s: with the old
  `$E000` buffer they overran it and read file data into their own code. Moving
  the buffer to `$FC00` fixed it — both build on **both** compilers now. (Was
  long misfiled as a "`p8cc.c` file-arg miscompile".) `diff` is the largest at
  ~17.6 KB on `p8cc.c`, so keep an eye on headroom there. NB the gap widened when
  `p8cc.py` gained a codegen-shrink (~17% tighter output) that has **not** been
  mirrored to `p8cc.c` (a deferred item) — so `p8cc.c`-built commands are now
  noticeably larger than the same source through `p8cc.py`.

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
