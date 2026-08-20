#!/bin/sh
# Build and run the P8X monitor + P8X/OS interactively in the emulator.
#   ./os/run.sh
# Assembles the ROM monitor and P8X/OS, builds the microcode, compiles the
# emulator, and makes a ready-to-boot P8XFS v2 disk (OS installed, plus a small
# sample tree incl. /bin/basic.bin — RUN it, then BYE to return). Then launches
# the emulator attached to your terminal: it starts
# in the MONITOR; type B to boot P8X/OS. Quit with Ctrl-C (or Ctrl-D).
#
# Commands ship twice: /bin holds the p8cc-compiled builds (run by bare name via
# PATH, e.g. `grep`), and /bina holds the hand-assembled counterparts from
# os/commands-asm (run explicitly, e.g. `run /bina/grep.bin`) so the two can be
# compared on-target. Their SOURCES ride along under /src/commands/{c,asm} so you
# can read (and, for C, `cc`-compile) any command right on the machine.
#
# Dual CompactFlash: a second data volume is attached as drive 1, mounted at
# /d1 in the unified namespace (a small sample tree under /d1/DATA). So you can
# exercise it out of the box with ordinary paths — `cd /d1`, `dir /d1/DATA`,
# `cat /d1/DATA/NOTES.TXT`, `cp /d1/DATA/NOTES.TXT /`. Drive 0 is the root.
#
# Both images persist between runs: os/run-disk.img (drive 0) and
# os/run-disk1.img (drive 1); delete either to start it fresh. Pass paths to
# use/keep different images:  ./os/run.sh mydisk0.img mydisk1.img
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
disk=${1:-"$root/os/run-disk.img"}
disk1=${2:-"$root/os/run-disk1.img"}
build=$(mktemp -d)

# Monitor + BIOS EEPROM. BASIC is no longer ROM-resident — it ships as the disk
# program /bin/basic.bin (installed below), so the EEPROM is just the monitor.
python3 "$root/assembler/p8xasm.py" "$root/firmware/p8xmon.asm" -o "$build/eeprom.bin" >/dev/null
python3 "$root/assembler/p8xasm.py" "$root/os/p8xos.asm" -o "$build/p8xos.bin" --base 0x2000 >/dev/null
( cd "$root/microcode" && python3 genucode.py >/dev/null )
cp "$root"/microcode/u?.bin "$build/"
cc -O2 -o "$build/p8xemu" "$root/emulator/p8xemu.c"
# Keep generated tables in sync with the ISA: the assembler opcode table (done
# per-build below) and the disassembler's opcode table — both the C form
# (os/commands/lib_distab.c, `//#use distab` in disasm.c) and the asm form
# (os/commands-asm/lib_distab.inc, `;#use distab` in disasm.asm).
python3 "$root/generators/gen_p8xdis.py" >/dev/null 2>&1 || true
python3 "$root/generators/gen_p8xdis.py" --asm >/dev/null 2>&1 || true

# ensure_src: lay down /src/commands/{c,asm} — the browsable command + toolchain
# SOURCES, mirroring the repo so you can read (and, for C, on-target `cc`-compile)
# any command right on the machine:
#   /src/commands/c    — the C command sources (the shared lib_*.c helpers are NOT
#                        duplicated here — they live only in /lib, where the native
#                        cc's //#use opens them: /lib/lib_<name>.c)
#   /src/commands/asm  — the hand-assembled command sources + the toolchain app
#                        sources p8xcc/p8xasm/p8xedit.asm. (The shared includes are
#                        NOT here; they live only in /lib as glob/globx/regex/
#                        stdin/distab.inc, where the on-target asm's ;#use reads them.)
# Idempotent and safe on a FRESH or EXISTING disk: mkdir/put are best-effort
# (p8xfs put never overwrites, so your files are kept and only MISSING sources are
# added — e.g. an older disk that predates a source gets it on the next run).
ensure_src() {
    for d in /src /src/commands /src/commands/c /src/commands/asm; do
        python3 "$root/tools/p8xfs.py" mkdir "$disk" "$d" >/dev/null 2>&1 || true
    done
    for cf in "$root"/os/commands/*.c; do
        base=$(basename "$cf")
        case "$base" in lib_*.c) continue;; esac             # shared libs live in /lib only
        python3 "$root/tools/p8xfs.py" put "$disk" "$cf" \
            --name "/src/commands/c/$base" >/dev/null 2>&1 || true
    done
    for af in "$root"/os/commands-asm/*.asm; do
        python3 "$root/tools/p8xfs.py" put "$disk" "$af" \
            --name "/src/commands/asm/$(basename "$af")" >/dev/null 2>&1 || true
    done
    # (the shared asm includes lib_*.inc are NOT copied here — like the C libs,
    #  they live only in /lib, where the on-target asm's ;#use opens /lib/<name>.inc)
    # p8xasm.asm is shipped specially below (with a trailing .include appended).
    for app in "$root"/apps/p8xcc.asm "$root"/apps/p8xedit.asm; do
        python3 "$root/tools/p8xfs.py" put "$disk" "$app" \
            --name "/src/commands/asm/$(basename "$app")" >/dev/null 2>&1 || true
    done
    # p8xasm needs the generated opcode table concatenated onto its source; ship the
    # table so the asm Makefile can build p8xasm on-target (cat opctab.asm then asm).
    # Fail loudly if generation breaks: a silently-empty/absent opctab.asm makes the
    # on-target `make p8xasm` die with `?undefined: OPCTAB`, which is baffling to debug.
    python3 "$root/generators/gen_p8xopc.py" "$build/opctab.asm" >/dev/null \
        || { echo "run.sh: gen_p8xopc.py failed" >&2; exit 1; }
    [ -s "$build/opctab.asm" ] && grep -q '^OPCTAB:' "$build/opctab.asm" \
        || { echo "run.sh: generated opctab.asm is empty or missing OPCTAB:" >&2; exit 1; }
    # Idempotent: on a reused disk opctab.asm is already present (p8xfs put has no
    # overwrite) — that's fine; only fail if it ends up neither shipped nor present.
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/opctab.asm" \
        --name /src/commands/asm/opctab.asm >/dev/null 2>&1 \
        || python3 "$root/tools/p8xfs.py" ls "$disk" /src/commands/asm 2>/dev/null \
             | grep -q '^opctab.asm ' \
        || { echo "run.sh: opctab.asm neither shipped nor already present" >&2; exit 1; }
    # Ship p8xasm.asm with a trailing `.include "opctab.asm"` so the on-target
    # Makefile can build it with a plain `asm p8xasm.asm` — no `cat` step. The
    # earlier recipe (`cat p8xasm.asm opctab.asm >T.ASM`) is doubly broken on
    # target: the on-target `cat` only ever emitted its first file arg, and even
    # once fixed, `cat A B >T.ASM` corrupts the first file because the redirect
    # write-stream and FRESOLVE's directory scan share SBUF. `.include` sidesteps
    # both by concatenating inside the assembler. (Host tests still cat the two
    # files — that path uses the host cat and is unaffected.)
    printf '%s\n        .include "opctab.asm"\n' "$(cat "$root/apps/p8xasm.asm")" > "$build/p8xasm_ondisk.asm"
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/p8xasm_ondisk.asm" \
        --name /src/commands/asm/p8xasm.asm >/dev/null 2>&1 \
        || python3 "$root/tools/p8xfs.py" ls "$disk" /src/commands/asm 2>/dev/null \
             | grep -q '^p8xasm.asm ' \
        || { echo "run.sh: p8xasm.asm neither shipped nor already present" >&2; exit 1; }
    # The OS + BIOS monitor are asm too — their sources ride under /src/os-bios/asm
    # with a build-output dir, and they assemble on-target with `asm`.
    # The monitor (58 KB) and the 121 KB OS both assemble on-target now — the BIOS
    # read/write streams are 24-bit (files up to 16 MB), so `asm` rebuilds both on-target.
    for d in /src/os-bios /src/os-bios/asm /src/os-bios/asm/bin /src/os-bios/generators; do
        python3 "$root/tools/p8xfs.py" mkdir "$disk" "$d" >/dev/null 2>&1 || true
    done
    python3 "$root/tools/p8xfs.py" put "$disk" "$root/firmware/p8xmon.asm" --name /src/os-bios/asm/p8xmon.asm >/dev/null 2>&1 || true
    python3 "$root/tools/p8xfs.py" put "$disk" "$root/os/p8xos.asm"        --name /src/os-bios/asm/p8xos.asm  >/dev/null 2>&1 || true
    # Bundle the memory map the OS/monitor sources `.include` — the LATEST generated
    # one at disk-creation time — at the path their `.include "../generators/
    # memmap.inc"` names (relative to /src/os-bios/asm). So the on-target OS build
    # has its single-source memory map alongside it.
    python3 "$root/tools/p8xfs.py" put "$disk" "$root/generators/memmap.inc" \
        --name /src/os-bios/generators/memmap.inc >/dev/null 2>&1 || true
    # On-target rebuild via the `make` built-in: each source dir carries a proper
    # Makefile (target: deps + TAB recipe; `all`/`clean`/`install` targets). `make`
    # reads the CWD Makefile and always rebuilds (no timestamps yet), so you `cd`
    # into a dir and build:
    #   cd /src/commands/c   && make pwd      one C command      -> bin/pwd.bin
    #   cd /src/commands/asm && make all      every asm command  -> bin/*.bin
    #   cd /src/os-bios      && make          the monitor + OS   -> asm/bin/*.bin
    #   ... && make clean                     delete that dir's build outputs
    #   ... && make install                   cp the built bin/*.bin -> /bin
    # Recipes run in the invoking CWD, so every path is dir-relative and short —
    # well under the 64-byte shell line buffer (disasm no longer needs an absolute
    # path, so its asm twin now rebuilds on-target too). `cc` writes its .asm to a
    # scratch T.ASM in the CWD (the shell registers the `>` redirect there); `asm`
    # reads that same relative T.ASM. Makefiles use LF line endings (the Unix
    # convention; EDIT writes LF too and make's line reader ends on CR or LF).
    for d in /src/commands/c/bin /src/commands/asm/bin; do
        python3 "$root/tools/p8xfs.py" mkdir "$disk" "$d" >/dev/null 2>&1 || true
    done
    # 23 dual-twin commands (each has a C source in commands/ and a hand-asm twin
    # in commands-asm/); disasm included — its relative recipe line now fits.
    _mkcmds="awk cat cmp cp dep diff dir disasm dump examine find grep head image man more mv pwd sed sort tail touch tree uniq vi wc"
    # C-only commands (no hand-asm twin yet) — they appear in the C Makefile only.
    # cube: the stage-7 wireframe-3D demo (lib_gfx + lib_g3d); its sine/edge
    # tables are brace-initialized arrays, fine for p8cc.py and the on-target cc
    # (the lib_distab/disasm precedent) but outside the p8cc.c self-host subset.
    _ccmds="cube"
    # --- /src/commands/c/Makefile : cc <cmd>.c >T.ASM ; asm T.ASM bin/<cmd>.bin
    mf="$build/Makefile.c"
    printf 'all:' > "$mf"; for c in $_mkcmds $_ccmds; do printf ' %s' "$c" >> "$mf"; done; printf '\n' >> "$mf"
    for c in $_mkcmds $_ccmds; do
        printf '%s:\n\tcc %s.c >T.ASM\n\tasm T.ASM bin/%s.bin\n' "$c" "$c" "$c" >> "$mf"
    done
    printf 'clean:\n' >> "$mf"; for c in $_mkcmds $_ccmds; do printf '\tdel bin/%s.bin\n' "$c" >> "$mf"; done
    # install: cp's glob needs an absolute dir (it doesn't CWD-prefix a relative
    # `bin/`), so name the source dir in full — this Makefile is dir-specific.
    printf 'install:\n\tcp /src/commands/c/bin/*.bin /bin\n' >> "$mf"
    python3 "$root/tools/p8xfs.py" put "$disk" "$mf" --name /src/commands/c/Makefile >/dev/null 2>&1 || true
    # --- /src/commands/asm/Makefile : asm <cmd>.asm bin/<cmd>.bin
    # Every .asm source in the dir gets a target: the 22 command twins (built
    # standalone) plus the toolchain apps p8xedit/p8xcc (standalone) and p8xasm
    # (its source is cat'd with the shipped opctab.asm first, since the opcode
    # table is generated, not part of the .asm).
    _asmapps="p8xedit p8xcc"
    mf="$build/Makefile.asm"
    printf 'all:' > "$mf"; for c in $_mkcmds $_asmapps p8xasm; do printf ' %s' "$c" >> "$mf"; done; printf '\n' >> "$mf"
    for c in $_mkcmds $_asmapps; do
        printf '%s:\n\tasm %s.asm bin/%s.bin\n' "$c" "$c" "$c" >> "$mf"
    done
    # p8xasm.asm is shipped with a trailing `.include "opctab.asm"` (see above),
    # so it builds with a plain asm — no cat, no T.ASM intermediate.
    printf 'p8xasm:\n\tasm p8xasm.asm bin/p8xasm.bin\n' >> "$mf"
    printf 'clean:\n' >> "$mf"
    for c in $_mkcmds $_asmapps p8xasm; do printf '\tdel bin/%s.bin\n' "$c" >> "$mf"; done
    printf 'install:\n\tcp /src/commands/asm/bin/*.bin /bin\n' >> "$mf"
    python3 "$root/tools/p8xfs.py" put "$disk" "$mf" --name /src/commands/asm/Makefile >/dev/null 2>&1 || true
    # --- /src/os-bios/Makefile : monitor + OS (sources under asm/, outputs asm/bin/)
    # NB: p8xmon.asm/p8xos.asm `.include "../generators/memmap.inc"` (bundled under
    # generators/ above); the native `asm` now supports `.include`, so these build
    # on-target too (slow — the OS is ~11 KB assembled).
    mf="$build/Makefile.osbios"
    printf 'all: mon os\n' > "$mf"
    printf 'mon:\n\tasm asm/p8xmon.asm asm/bin/p8xmon.bin\n' >> "$mf"
    printf 'os:\n\tasm asm/p8xos.asm asm/bin/p8xos.bin\n' >> "$mf"
    printf 'clean:\n\tdel asm/bin/p8xmon.bin\n\tdel asm/bin/p8xos.bin\n' >> "$mf"
    python3 "$root/tools/p8xfs.py" put "$disk" "$mf" --name /src/os-bios/Makefile >/dev/null 2>&1 || true
}

if [ ! -f "$disk" ]; then
    # Fresh v2 disk: install the OS and lay down a small sample tree so DIR/
    # tree/cd/run have something to show.
    python3 "$root/tools/p8xfs.py" create "$disk" --v2 >/dev/null
    python3 "$root/tools/p8xfs.py" boot   "$disk" "$build/p8xos.bin" >/dev/null
    python3 "$root/tools/p8xfs.py" mkdir  "$disk" /bin >/dev/null
    # /bina: the hand-assembled counterparts of the /bin commands (the
    # os/commands-asm experiment), so both can be run and compared on-target,
    # e.g.  run /bina/grep.bin ...  vs  run /bin/grep.bin ...
    python3 "$root/tools/p8xfs.py" mkdir  "$disk" /bina >/dev/null
    # /d1 mount point: a placeholder dir so `dir /` shows the mount. Traversal
    # into /d1 is intercepted by the resolver (redirected to drive 1) before this
    # empty placeholder is ever read — it is just a signpost.
    python3 "$root/tools/p8xfs.py" mkdir  "$disk" /d1 >/dev/null
    # a tiny program (prints "HI") so RUN /bin/hi.bin works
    printf '        .org $6A00\n        LDA #%cH%c\n        JSR $0103\n        LDA #%cI%c\n        JSR $0103\n        LDA #$0D\n        JSR $0103\n        LDA #$0A\n        JSR $0103\n        RTS\n' "'" "'" "'" "'" > "$build/hi.asm"
    python3 "$root/assembler/p8xasm.py" "$build/hi.asm" -o "$build/hi.bin" --base 0x6A00 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/hi.bin" --name /bin/hi.bin >/dev/null
    # OS-runnable BASIC: TPA build (code+data+scratch in $B000.., clear of the OS)
    # whose BYE returns to the OS cold start -> RUN /bin/basic.bin, then BYE.
    python3 "$root/assembler/p8xasm.py" "$root/basic/p8xbasic.asm" -o "$build/basicrun.bin" \
        --base 0x6A00 -D BASORG=0x6A00 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x2000 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/basicrun.bin" \
        --name /bin/basic.bin --load 0x6A00 --exec 0x6A00 >/dev/null
    # EDIT: line-oriented text editor (TPA program) -> RUN /bin/edit.bin NAME
    python3 "$root/assembler/p8xasm.py" "$root/apps/p8xedit.asm" -o "$build/edit.bin" \
        --base 0x6A00 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/edit.bin" \
        --name /bin/edit.bin --load 0x6A00 --exec 0x6A00 >/dev/null
    # ASM: native two-pass assembler (logic + generated opcode table) -> RUN
    # /bin/asm.bin SRC.ASM OUT.BIN.  Pair with EDIT for an on-target toolchain.
    python3 "$root/generators/gen_p8xopc.py" "$build/opctab.asm"
    cat "$root/apps/p8xasm.asm" "$build/opctab.asm" > "$build/asmfull.asm"
    python3 "$root/assembler/p8xasm.py" "$build/asmfull.asm" -o "$build/asm.bin" \
        --base 0x6A00 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/asm.bin" \
        --name /bin/asm.bin --load 0x6A00 --exec 0x6A00 >/dev/null
    # CC: the native C compiler, hand-written in asm (Milestone B, path B) -> RUN
    # /bin/cc.bin SRC.C >OUT.ASM.  Chains with asm to compile C entirely on-target.
    python3 "$root/assembler/p8xasm.py" "$root/apps/p8xcc.asm" -o "$build/cc.bin" \
        --base 0x6A00 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/cc.bin" \
        --name /bin/cc.bin --load 0x6A00 --exec 0x6A00 >/dev/null
    # The native `cc` (apps/p8xcc.asm) does the WHOLE compile on-target, so the
    # older split front end (cpp | lex | cc1) was retired (2026-07-14). The
    # //#use splicing that cpp performed lives host-side as tools/clib.py (used
    # just below to build every /bin command).
    # C-as-OS-commands (compiled with p8cc): demonstrate the OS syscalls, I/O
    # redirection and pipes out of the box. Run by bare name via PATH (/bin),
    # e.g.  dir /bin ,  cat README.TXT ,  cat README.TXT | grep hello | wc ,
    # cp README.TXT COPY.TXT ,  mv COPY.TXT MOVED.TXT .
    for ex in dir pwd cat wc grep cp mv head tail more sort uniq sed find diff tree vi touch man dep dump examine disasm awk cmp cube image; do
        # clib.py splices any //#use lib_*.c (shared helpers) into the source first;
        # a no-op passthrough for commands with no //#use directive.
        python3 "$root/tools/clib.py" "$root/os/commands/$ex.c" -o "$build/$ex.c"
        python3 "$root/compiler/p8cc.py" "$build/$ex.c" -o "$build/$ex.asm" >/dev/null
        python3 "$root/assembler/p8xasm.py" "$build/$ex.asm" -o "$build/$ex.bin" --base 0x6A00 >/dev/null
        python3 "$root/tools/p8xfs.py" put "$disk" "$build/$ex.bin" \
            --name "/bin/$ex.bin" --load 0x6A00 --exec 0x6A00 >/dev/null
    done
    # Hand-assembled versions -> /bina (os/commands-asm). mkasm.sh splices any
    # ;#use includes (lib_stdin/glob/regex/distab) just like clib.py does for C.
    for ex in dir pwd cat wc grep cp mv head tail more sort uniq sed find diff tree vi touch man dep dump examine disasm awk cmp image; do
        sh "$root/os/commands-asm/mkasm.sh" "$ex" > "$build/$ex.a.asm"
        python3 "$root/assembler/p8xasm.py" "$build/$ex.a.asm" -o "$build/$ex.a.bin" --base 0x6A00 >/dev/null
        python3 "$root/tools/p8xfs.py" put "$disk" "$build/$ex.a.bin" \
            --name "/bina/$ex.bin" --load 0x6A00 --exec 0x6A00 >/dev/null
    done
    # /man: a Unix-style manual page per command (plain text in os/man/). The
    # `man` command (installed above) reads /man/<name>, so `man dir` works.
    python3 "$root/tools/p8xfs.py" mkdir "$disk" /man >/dev/null
    for page in "$root"/os/man/*; do
        base=$(basename "$page")
        [ "$base" = "README.md" ] && continue      # repo doc, not a man page
        python3 "$root/tools/p8xfs.py" put "$disk" "$page" \
            --name "/man/$base" >/dev/null
    done
    # /lib: the shared C library sources (lib_*.c). The native `cc`'s //#use
    # splicer opens /lib/lib_<name>.c on-target (its counterpart of clib.py), so
    # e.g. `cc wc.c` can pull in `//#use stdin`. Plain source, not compiled here.
    python3 "$root/tools/p8xfs.py" mkdir "$disk" /lib >/dev/null
    for libc in "$root"/os/commands/lib_*.c; do
        python3 "$root/tools/p8xfs.py" put "$disk" "$libc" \
            --name "/lib/$(basename "$libc")" >/dev/null
    done
    # ...and the shared ASM includes, so the on-target assembler's `;#use NAME`
    # can splice /lib/NAME.inc (its counterpart of mkasm.sh) — e.g. `asm cat.asm`
    # pulls in `;#use stdin`. Named NAME.inc (lib_ dropped) to fit the 12-char field.
    for inc in "$root"/os/commands-asm/lib_*.inc; do
        base=$(basename "$inc"); base=${base#lib_}
        python3 "$root/tools/p8xfs.py" put "$disk" "$inc" \
            --name "/lib/$base" >/dev/null
    done
    ensure_src            # /src/commands/{c,asm}: browsable sources (see the function)
    printf 'hello from P8X/OS\n' > "$build/readme.txt"
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/readme.txt" --name /README.TXT >/dev/null
    # The demo photo for BASIC's IMAGE statement (P8I, made with tools/p8img.py):
    # IMAGE 112,8,"/MANDRILL.P8I". Tracked in the repo so a fresh disk has it.
    python3 "$root/tools/p8xfs.py" put "$disk" "$root/os/mandrill.p8i" \
        --name /MANDRILL.P8I >/dev/null
    # A sample assembly source so the EDIT -> ASM -> RUN loop is demoable out of
    # the box: run /bin/edit.bin hello.asm (look/edit), then
    # run /bin/asm.bin hello.asm hello.bin, then run hello.bin -> prints HELLO.
    cat > "$build/hello.asm" <<'ASMEOF'
; sample program -- assemble with: run /bin/asm.bin hello.asm hello.bin
        .org $6A00
        LDP1 #msg
lp:     LDA  (P1)+
        JZ   done
        JSR  $0103
        JMP  lp
done:   RTS
msg:    .asciiz "HELLO FROM P8X ASM"
ASMEOF
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/hello.asm" --name /hello.asm >/dev/null
    echo "created fresh disk: $disk"
else
    # Snapshot the disk's mtime BEFORE we touch it (the boot below rewrites it).
    touch -r "$disk" "$build/diskref"
    # Reinstall the freshly-built OS into the existing disk (keeps your files).
    python3 "$root/tools/p8xfs.py" boot "$disk" "$build/p8xos.bin" >/dev/null
    ensure_src   # add /src (and any sources missing on an older disk) without touching your files
    echo "using existing disk: $disk (refreshed OS + /src sources)"
    # The OS boot is refreshed above, but the bundled /bin programs (dir, cat,
    # BASIC, EDIT, ASM ...) are NOT — p8xfs put won't overwrite, and we won't
    # wipe a disk that may hold your files. So if any program/OS source is newer
    # than the disk's pre-run mtime, its /bin/*.bin is stale here. Warn loudly.
    newer=$(find "$root/os/commands" "$root/os/commands-asm" "$root/os/p8xos.asm" \
                 "$root/compiler/p8cc.py" "$root/basic" "$root/apps" -type f \
                 -newer "$build/diskref" 2>/dev/null | head -5)
    if [ -n "$newer" ]; then
        echo "WARNING: these sources are newer than $disk, but the disk's /bin" >&2
        echo "         programs are NOT rebuilt on an existing disk:" >&2
        echo "$newer" | sed 's,^,           ,' >&2
        echo "         To pick up the changes, rebuild the disk:" >&2
        echo "           rm \"$disk\" && $0 ${1:+\"$1\"}" >&2
        echo "         (this recreates the sample tree; copy out any files you made first)." >&2
    fi
fi

# Drive 1: a second CF, a plain data volume (not bootable — OSCNT stays 0). Lay
# down a small /DATA tree so `1:` then `dir`, and `0:`/`1:` prefixes, have
# something to show. Persists at os/run-disk1.img; delete it to recreate.
if [ ! -f "$disk1" ]; then
    python3 "$root/tools/p8xfs.py" create "$disk1" --v2 >/dev/null
    python3 "$root/tools/p8xfs.py" mkdir  "$disk1" /DATA >/dev/null
    printf 'this file lives on drive 1\n' > "$build/notes.txt"
    python3 "$root/tools/p8xfs.py" put "$disk1" "$build/notes.txt" --name /DATA/NOTES.TXT >/dev/null
    printf 'drive one root file\n' > "$build/d1root.txt"
    python3 "$root/tools/p8xfs.py" put "$disk1" "$build/d1root.txt" --name /HELLO1.TXT >/dev/null
    echo "created fresh drive-1 disk: $disk1"
else
    echo "using existing drive-1 disk: $disk1"
fi

# Headless build-only mode (P8X_BUILD_ONLY=1): the full disk images are built
# above; skip the interactive emulator. Used by the system-build test to get a
# complete, ready-to-boot volume without launching a terminal session. The built
# eeprom + emulator are copied next to the images so a caller can boot them.
if [ -n "$P8X_BUILD_ONLY" ]; then
    # copy the boot bits next to the images: eeprom, the emulator, AND the
    # microcode u?.bin (the emulator loads microcode from its CWD).
    cp "$build/eeprom.bin" "$build/p8xemu" "$build"/u?.bin "$(dirname "$disk")/" 2>/dev/null || true
    echo "built (headless): $disk  +  $disk1"
    exit 0
fi

echo "--- starting emulator: you are in the MONITOR (* prompt). Type B to boot P8X/OS. ---"
echo "--- drive 0 = $disk  |  drive 1 = $disk1 (mounted at /d1) ---"
cd "$build"
exec ./p8xemu -L -c "$disk" -c2 "$disk1" eeprom.bin   # writes persist to both images
