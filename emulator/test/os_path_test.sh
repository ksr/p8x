#!/bin/sh
# Implicit RUN: a bare command name that isn't a built-in is looked up as a
# program along PATH (default "/BIN"), trying "<dir>/<name>" then
# "<dir>/<name>.BIN". A name containing '/' is run as a literal path. Args after
# the command word reach the program (P2 arg tail), and a name that resolves
# nowhere prints the unknown-command marker. Shell redirects still apply.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "OS-PATH TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

# A program that is NOT a built-in command (so it can only run via PATH lookup):
# prints a banner, then echoes its argument tail.
cat > greet.c <<'EOF'
int main() {
    char *a;
    puts("GREETOK");
    a = argstr();
    while (*a == 32) { a = a + 1; }
    while (*a != 0 && *a != 13) { putchar(*a); a = a + 1; }
    putchar(10);
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py greet.c -o g.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py g.asm -o g.bin --base 0xB000 >/dev/null

rm -f path.img
python3 $ROOT/tools/p8xfs.py create path.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   path.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  path.img /BIN >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  path.img /SUB >/dev/null
python3 $ROOT/tools/p8xfs.py put    path.img g.bin --name /BIN/GREET.BIN --load 0xB000 --exec 0xB000 >/dev/null

run() {  # $1 = command line typed at the OS prompt -> stripped console output
    printf "B\r$1\r" | ../p8xemu -l 250000000 -c path.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r'
}

# 1) bare name resolves via PATH=/BIN with the .BIN suffix appended
echo "$(run 'GREET')"        | grep -q 'GREETOK'   || fail "bare GREET did not run /BIN/GREET.BIN"
# 2) the argument tail reaches the program
echo "$(run 'GREET HELLO')"  | grep -qx 'HELLO'    || fail "args not passed to an implicitly-run program"
# 3) a name containing '/' runs as a literal path (no PATH prefix)
echo "$(run '/BIN/GREET.BIN')"| grep -q 'GREETOK'  || fail "literal /BIN/GREET.BIN did not run"
# 4) PATH is absolute, so a bare name works from any CWD
echo "$(run 'CD /SUB\rGREET')" | grep -q 'GREETOK'  || fail "bare GREET failed from a non-root CWD"
# 5) a name that resolves nowhere is reported, not silently run
echo "$(run 'NOSUCHCMD')"    | grep -q '?'         || fail "unknown command not reported"
# 6) explicit RUN still works (refactor regression guard)
echo "$(run 'RUN /BIN/GREET.BIN ARG1')" | grep -qx 'ARG1' || fail "explicit RUN broke (arg tail)"
# 7) a bare implicit run can be redirected to a file
run 'GREET >OUT.TXT' >/dev/null
python3 $ROOT/tools/p8xfs.py get path.img OUT.TXT --out po.txt >/dev/null 2>&1 || fail "implicit run not redirectable"
grep -q 'GREETOK' po.txt || fail "redirected implicit-run output wrong"

echo "OS-PATH TEST: PASS"
