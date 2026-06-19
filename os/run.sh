#!/bin/sh
# Build and run the P8X monitor + P8X/OS interactively in the emulator.
#   ./os/run.sh
# Assembles the ROM monitor and P8X/OS, builds the microcode, compiles the
# emulator, and makes a ready-to-boot P8XFS v2 disk (OS installed, plus a small
# sample tree). Then launches the emulator attached to your terminal: it starts
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
python3 "$root/assembler/p8xasm.py" "$root/os/p8xos.asm" -o "$build/p8xos.bin" --base 0x8000 >/dev/null
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
    printf 'hello from P8X/OS\n' > "$build/readme.txt"
    python3 "$root/tools/p8xfs.py" put "$disk" "$build/readme.txt" --name /README.TXT >/dev/null
    echo "created fresh disk: $disk"
else
    # Reinstall the freshly-built OS into the existing disk (keeps your files).
    python3 "$root/tools/p8xfs.py" boot "$disk" "$build/p8xos.bin" >/dev/null
    echo "using existing disk: $disk"
fi

echo "--- starting emulator: you are in the MONITOR (* prompt). Type B to boot P8X/OS. ---"
cd "$build"
exec ./p8xemu -c "$disk" eeprom.bin   # writes persist to the disk image
