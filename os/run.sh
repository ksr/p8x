#!/bin/sh
# Build and run the P8X monitor + P8X/OS interactively in the emulator.
#   ./os/run.sh
# Assembles the ROM monitor and P8X/OS, builds the microcode, compiles the
# emulator, and makes a ready-to-boot P8XFS v2 disk (OS installed, plus a small
# sample tree incl. /BIN/BASIC.BIN — RUN it, then BYE to return). Then launches
# the emulator attached to your terminal: it starts
# in the MONITOR; type B to boot P8X/OS. Quit with Ctrl-C (or Ctrl-D).
#
# The disk image persists at os/run-disk.img between runs (delete it to start
# fresh). Pass a path to use/keep a different image:  ./os/run.sh mydisk.img
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
disk=${1:-"$root/os/run-disk.img"}
build=$(mktemp -d)

# Combined monitor + ROM-BASIC EEPROM, so the monitor's X command can launch
# BASIC (a bare-monitor build has nothing at $2000 and X would crash).
python3 "$root/tools/build_basic_rom.py" "$build/eeprom.bin" >/dev/null
python3 "$root/assembler/p8xasm.py" "$root/os/p8xos.asm" -o "$build/p8xos.bin" --base 0x4000 >/dev/null
( cd "$root/microcode" && python3 genucode.py >/dev/null )
cp "$root"/microcode/u?.bin "$build/"
cc -O2 -o "$build/p8xemu" "$root/emulator/p8xemu.c"

if [ ! -f "$disk" ]; then
    # Fresh v2 disk: install the OS and lay down a small sample tree so DIR/
    # TREE/CD/RUN have something to show.
    python3 "$root/tools/p8xfs.py" create "$disk" --v2 >/dev/null
    python3 "$root/tools/p8xfs.py" boot   "$disk" "$build/p8xos.bin" >/dev/null
    python3 "$root/tools/p8xfs.py" mkdir  "$disk" /BIN >/dev/null
    # a tiny program (prints "HI") so RUN /BIN/HI.BIN works
    printf '        .org $B000\n        LDA #%cH%c\n        JSR $0103\n        LDA #%cI%c\n        JSR $0103\n        LDA #$0D\n        JSR $0103\n        LDA #$0A\n        JSR $0103\n        RTS\n' "'" "'" "'" "'" > "$build/hi.asm"
    python3 "$root/assembler/p8xasm.py" "$build/hi.asm" -o "$build/hi.bin" --base 0xB000 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/hi.bin" --name /BIN/HI.BIN >/dev/null
    # OS-runnable BASIC: TPA build (code+data+scratch in $B000.., clear of the OS)
    # whose BYE returns to the OS cold start -> RUN /BIN/BASIC.BIN, then BYE.
    python3 "$root/assembler/p8xasm.py" "$root/basic/p8xbasic.asm" -o "$build/basicrun.bin" \
        --base 0xB000 -D BASORG=0xB000 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x4000 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/basicrun.bin" \
        --name /BIN/BASIC.BIN --load 0xB000 --exec 0xB000 >/dev/null
    # EDIT: line-oriented text editor (TPA program) -> RUN /BIN/EDIT.BIN NAME
    python3 "$root/assembler/p8xasm.py" "$root/apps/p8xedit.asm" -o "$build/edit.bin" \
        --base 0xB000 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/edit.bin" \
        --name /BIN/EDIT.BIN --load 0xB000 --exec 0xB000 >/dev/null
    # ASM: native two-pass assembler (logic + generated opcode table) -> RUN
    # /BIN/ASM.BIN SRC.ASM OUT.BIN.  Pair with EDIT for an on-target toolchain.
    python3 "$root/generators/gen_p8xopc.py" "$build/opctab.asm"
    cat "$root/apps/p8xasm.asm" "$build/opctab.asm" > "$build/asmfull.asm"
    python3 "$root/assembler/p8xasm.py" "$build/asmfull.asm" -o "$build/asm.bin" \
        --base 0xB000 >/dev/null
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/asm.bin" \
        --name /BIN/ASM.BIN --load 0xB000 --exec 0xB000 >/dev/null
    # C-as-OS-commands (compiled with p8cc): demonstrate the OS syscalls, I/O
    # redirection and pipes out of the box. Run by bare name via PATH (/BIN),
    # e.g.  DIR /BIN ,  CAT README.TXT ,  CAT README.TXT | GREP hello | WC ,
    # CP README.TXT COPY.TXT ,  MV COPY.TXT MOVED.TXT .
    for ex in dir pwd cat wc grep cp mv head tail more sort uniq sed; do
        python3 "$root/compiler/p8cc.py" "$root/os/commands/$ex.c" -o "$build/$ex.asm" >/dev/null
        python3 "$root/assembler/p8xasm.py" "$build/$ex.asm" -o "$build/$ex.bin" --base 0xB000 >/dev/null
        up=$(echo "$ex" | tr a-z A-Z)
        python3 "$root/tools/p8xfs.py" put "$disk" "$build/$ex.bin" \
            --name "/BIN/$up.BIN" --load 0xB000 --exec 0xB000 >/dev/null
    done
    printf 'hello from P8X/OS\n' > "$build/readme.txt"
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/readme.txt" --name /README.TXT >/dev/null
    # A sample assembly source so the EDIT -> ASM -> RUN loop is demoable out of
    # the box: RUN /BIN/EDIT.BIN HELLO.ASM (look/edit), then
    # RUN /BIN/ASM.BIN HELLO.ASM HELLO.BIN, then RUN HELLO.BIN -> prints HELLO.
    cat > "$build/hello.asm" <<'ASMEOF'
; sample program -- assemble with: RUN /BIN/ASM.BIN HELLO.ASM HELLO.BIN
        .org $B000
        LDP1 #msg
lp:     LDA  (P1)+
        JZ   done
        JSR  $0103
        JMP  lp
done:   RTS
msg:    .asciiz "HELLO FROM P8X ASM"
ASMEOF
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/hello.asm" --name /HELLO.ASM >/dev/null
    echo "created fresh disk: $disk"
else
    # Snapshot the disk's mtime BEFORE we touch it (the boot below rewrites it).
    touch -r "$disk" "$build/diskref"
    # Reinstall the freshly-built OS into the existing disk (keeps your files).
    python3 "$root/tools/p8xfs.py" boot "$disk" "$build/p8xos.bin" >/dev/null
    echo "using existing disk: $disk"
    # The OS boot is refreshed above, but the bundled /BIN programs (DIR, CAT,
    # BASIC, EDIT, ASM ...) are NOT — p8xfs put won't overwrite, and we won't
    # wipe a disk that may hold your files. So if any program/OS source is newer
    # than the disk's pre-run mtime, its /BIN/*.BIN is stale here. Warn loudly.
    newer=$(find "$root/os/commands" "$root/os/p8xos.asm" "$root/compiler/p8cc.py" \
                 "$root/basic" "$root/apps" -type f -newer "$build/diskref" 2>/dev/null | head -5)
    if [ -n "$newer" ]; then
        echo "WARNING: these sources are newer than $disk, but the disk's /BIN" >&2
        echo "         programs are NOT rebuilt on an existing disk:" >&2
        echo "$newer" | sed 's,^,           ,' >&2
        echo "         To pick up the changes, rebuild the disk:" >&2
        echo "           rm \"$disk\" && $0 ${1:+\"$1\"}" >&2
        echo "         (this recreates the sample tree; copy out any files you made first)." >&2
    fi
fi

echo "--- starting emulator: you are in the MONITOR (* prompt). Type B to boot P8X/OS. ---"
cd "$build"
exec ./p8xemu -L -c "$disk" eeprom.bin   # writes persist to the disk image
