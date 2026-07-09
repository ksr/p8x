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
# compared on-target.
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
python3 "$root/assembler/p8xasm.py" "$root/os/p8xos.asm" -o "$build/p8xos.bin" --base 0x4000 >/dev/null
( cd "$root/microcode" && python3 genucode.py >/dev/null )
cp "$root"/microcode/u?.bin "$build/"
cc -O2 -o "$build/p8xemu" "$root/emulator/p8xemu.c"

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
    printf '        .org $7A00\n        LDA #%cH%c\n        JSR $0103\n        LDA #%cI%c\n        JSR $0103\n        LDA #$0D\n        JSR $0103\n        LDA #$0A\n        JSR $0103\n        RTS\n' "'" "'" "'" "'" > "$build/hi.asm"
    python3 "$root/assembler/p8xasm.py" "$build/hi.asm" -o "$build/hi.bin" --base 0x7A00 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/hi.bin" --name /bin/hi.bin >/dev/null
    # OS-runnable BASIC: TPA build (code+data+scratch in $B000.., clear of the OS)
    # whose BYE returns to the OS cold start -> RUN /bin/basic.bin, then BYE.
    python3 "$root/assembler/p8xasm.py" "$root/basic/p8xbasic.asm" -o "$build/basicrun.bin" \
        --base 0x7A00 -D BASORG=0x7A00 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x4000 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/basicrun.bin" \
        --name /bin/basic.bin --load 0x7A00 --exec 0x7A00 >/dev/null
    # EDIT: line-oriented text editor (TPA program) -> RUN /bin/edit.bin NAME
    python3 "$root/assembler/p8xasm.py" "$root/apps/p8xedit.asm" -o "$build/edit.bin" \
        --base 0x7A00 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/edit.bin" \
        --name /bin/edit.bin --load 0x7A00 --exec 0x7A00 >/dev/null
    # ASM: native two-pass assembler (logic + generated opcode table) -> RUN
    # /bin/asm.bin SRC.ASM OUT.BIN.  Pair with EDIT for an on-target toolchain.
    python3 "$root/generators/gen_p8xopc.py" "$build/opctab.asm"
    cat "$root/apps/p8xasm.asm" "$build/opctab.asm" > "$build/asmfull.asm"
    python3 "$root/assembler/p8xasm.py" "$build/asmfull.asm" -o "$build/asm.bin" \
        --base 0x7A00 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/asm.bin" \
        --name /bin/asm.bin --load 0x7A00 --exec 0x7A00 >/dev/null
    # CPP: the //#use source preprocessor, pass 1 of the on-target C toolchain
    # (native counterpart of tools/clib.py). C-only — a compiler pass, not a dual
    # C+asm command, so no /bina twin (like edit/asm are asm-only).
    python3 "$root/tools/clib.py"    "$root/os/commands/cpp.c" -o "$build/cpp.c"
    python3 "$root/compiler/p8cc.py" "$build/cpp.c" -o "$build/cpp.asm" >/dev/null
    python3 "$root/assembler/p8xasm.py" "$build/cpp.asm" -o "$build/cpp.bin" --base 0x7A00 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/cpp.bin" \
        --name /bin/cpp.bin --load 0x7A00 --exec 0x7A00 >/dev/null
    # LEX: the tokenizer, pass 2 of the on-target C toolchain (native counterpart
    # of p8cc.py's lexer). C-only, same as cpp — a compiler pass, no /bina twin.
    python3 "$root/tools/clib.py"    "$root/os/commands/lex.c" -o "$build/lex.c"
    python3 "$root/compiler/p8cc.py" "$build/lex.c" -o "$build/lex.asm" >/dev/null
    python3 "$root/assembler/p8xasm.py" "$build/lex.asm" -o "$build/lex.bin" --base 0x7A00 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/lex.bin" \
        --name /bin/lex.bin --load 0x7A00 --exec 0x7A00 >/dev/null
    # C-as-OS-commands (compiled with p8cc): demonstrate the OS syscalls, I/O
    # redirection and pipes out of the box. Run by bare name via PATH (/bin),
    # e.g.  dir /bin ,  cat README.TXT ,  cat README.TXT | grep hello | wc ,
    # cp README.TXT COPY.TXT ,  mv COPY.TXT MOVED.TXT .
    for ex in dir pwd cat wc grep cp mv head tail more sort uniq sed find diff tree vi touch man dep dump; do
        # clib.py splices any //#use lib_*.c (shared helpers) into the source first;
        # a no-op passthrough for commands with no //#use directive.
        python3 "$root/tools/clib.py" "$root/os/commands/$ex.c" -o "$build/$ex.c"
        python3 "$root/compiler/p8cc.py" "$build/$ex.c" -o "$build/$ex.asm" >/dev/null
        python3 "$root/assembler/p8xasm.py" "$build/$ex.asm" -o "$build/$ex.bin" --base 0x7A00 >/dev/null
        python3 "$root/tools/p8xfs.py" put "$disk" "$build/$ex.bin" \
            --name "/bin/$ex.bin" --load 0x7A00 --exec 0x7A00 >/dev/null
    done
    # Hand-assembled versions -> /bina (os/commands-asm). mkasm.sh splices any
    # ;#use includes (lib_stdin/glob/regex) just like clib.py does for the C ones.
    for ex in dir pwd cat wc grep cp mv head tail more sort uniq sed find diff tree vi touch man dep dump; do
        sh "$root/os/commands-asm/mkasm.sh" "$ex" > "$build/$ex.a.asm"
        python3 "$root/assembler/p8xasm.py" "$build/$ex.a.asm" -o "$build/$ex.a.bin" --base 0x7A00 >/dev/null
        python3 "$root/tools/p8xfs.py" put "$disk" "$build/$ex.a.bin" \
            --name "/bina/$ex.bin" --load 0x7A00 --exec 0x7A00 >/dev/null
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
    printf 'hello from P8X/OS\n' > "$build/readme.txt"
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/readme.txt" --name /README.TXT >/dev/null
    # A sample assembly source so the EDIT -> ASM -> RUN loop is demoable out of
    # the box: run /bin/edit.bin hello.asm (look/edit), then
    # run /bin/asm.bin hello.asm hello.bin, then run hello.bin -> prints HELLO.
    cat > "$build/hello.asm" <<'ASMEOF'
; sample program -- assemble with: run /bin/asm.bin hello.asm hello.bin
        .org $7A00
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
    echo "using existing disk: $disk"
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

echo "--- starting emulator: you are in the MONITOR (* prompt). Type B to boot P8X/OS. ---"
echo "--- drive 0 = $disk  |  drive 1 = $disk1 (mounted at /d1) ---"
cd "$build"
exec ./p8xemu -L -c "$disk" -c2 "$disk1" eeprom.bin   # writes persist to both images
