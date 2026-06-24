#!/bin/sh
# Shell pipes ("cmd1 | cmd2"): with no multitasking, the shell runs cmd1 with its
# stdout to a temp file (PIPE.TMP), then re-dispatches cmd2 with its stdin from
# that file, then deletes it — a SHELL state machine over the < / > redirection
# already built.  A producer (puts "PIPEDATA") piped into cat.c must put
# PIPEDATA on the console.  Compiled by BOTH p8cc.py and the native p8cc.c.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-PIPE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null
cat > prod.c <<'EOF'
int main() { puts("PIPEDATA"); return 0; }
EOF

check() {   # $1 = label, $2 = prod.asm, $3 = cat.asm
    python3 $ROOT/assembler/p8xasm.py "$2" -o prod.bin --base 0xB000 >/dev/null
    python3 $ROOT/assembler/p8xasm.py "$3" -o cat.bin  --base 0xB000 >/dev/null
    rm -f pp.img
    python3 $ROOT/tools/p8xfs.py create pp.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   pp.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py put    pp.img prod.bin --name PROD.BIN --load 0xB000 --exec 0xB000 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    pp.img cat.bin  --name CAT.BIN  --load 0xB000 --exec 0xB000 >/dev/null
    out=$(printf 'B\rRUN /PROD.BIN | RUN /CAT.BIN\r' | ../p8xemu -l 200000000 -c pp.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | sed -n '/PROD.BIN/,$p' | grep -v 'PROD.BIN' | tr -dc 'A-Z')
    [ "$out" = "PIPEDATA" ] || fail "$1: pipe output '$out' != 'PIPEDATA'"
    if python3 $ROOT/tools/p8xfs.py ls pp.img / 2>&1 | grep -qi 'PIPE.TMP'; then
        fail "$1: PIPE.TMP not cleaned up"
    fi
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    ./p8cc_host < prod.c > prh.asm
    ./p8cc_host < $ROOT/compiler/examples/cat.c > cah.asm
    check "p8cc.c" prh.asm cah.asm
fi

python3 $ROOT/compiler/p8cc.py prod.c -o prp.asm >/dev/null
python3 $ROOT/compiler/p8cc.py $ROOT/compiler/examples/cat.c -o cap.asm >/dev/null
check "p8cc.py" prp.asm cap.asm

echo "C-PIPE TEST: PASS"
