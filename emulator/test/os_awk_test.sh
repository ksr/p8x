#!/bin/sh
# awk (os/commands/awk.c): field-oriented text processing. Split on whitespace
# (or -F c), select lines by /regex/, and `print` fields / NR / NF / literals.
# Reads a file arg or a pipe. C-only command.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-AWK TEST: FAIL — $1"; [ -n "$2" ] && printf '%s\n' "$2"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osawk.bin --base 0x2000 >/dev/null
for c in awk cat; do
    python3 $ROOT/tools/clib.py $ROOT/os/commands/$c.c -o $c.pp.c
    python3 $ROOT/compiler/p8cc.py $c.pp.c -o $c.a2.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py $c.a2.asm -o $c.a2.bin --base 0x6A00 >/dev/null
done
rm -f awk.img
python3 $ROOT/tools/p8xfs.py create awk.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   awk.img osawk.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  awk.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    awk.img awk.a2.bin --name /bin/awk.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    awk.img cat.a2.bin --name /bin/cat.bin --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'one two three\nfoo bar\nalpha beta gamma delta\n' > d.txt
python3 $ROOT/tools/p8xfs.py put    awk.img d.txt --name /D.TXT >/dev/null
printf 'root:x:0\nken:y:1000\n' > p.txt
python3 $ROOT/tools/p8xfs.py put    awk.img p.txt --name /P.TXT >/dev/null

# R <cmdline> <anchor> -> the command's output lines (between the echoed command
# line and the next prompt), prompts/blanks stripped.
R() { printf "B\r$1\r" | ../p8xemu -l 300000000 -c awk.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | sed -n "/$2/,/^\/> \$/p" | grep -v '^/> ' | grep -v '^$'; }

# field print
out=$(R "awk '{print \$2}' D.TXT" 'print .2')
printf '%s\n' "$out" | grep -qx 'two'  || fail "print \$2 missed 'two'"  "$out"
printf '%s\n' "$out" | grep -qx 'beta' || fail "print \$2 missed 'beta'" "$out"
# $NF (last field)
printf '%s\n' "$(R "awk '{print \$NF}' D.TXT" 'NF.. D')" | grep -qx 'delta' || fail "\$NF missed 'delta'"
# /regex/ selection
printf '%s\n' "$(R "awk '/foo/{print}' D.TXT" 'foo..print')" | grep -qx 'foo bar' || fail "/foo/ did not print the matching line"
# bare pattern -> print the line
printf '%s\n' "$(R "awk '/alpha/' D.TXT" 'alpha.. D')" | grep -qx 'alpha beta gamma delta' || fail "bare /alpha/ did not print the line"
# -F separator
printf '%s\n' "$(R "awk -F: '{print \$1}' P.TXT" 'print .1.. P')" | grep -qx 'ken' || fail "-F: print \$1 missed 'ken'"
# NR, NF
out=$(R "awk '{print NR, NF}' D.TXT" 'NR, NF')
printf '%s\n' "$out" | grep -qx '1 3' || fail "NR,NF wrong for line 1" "$out"
printf '%s\n' "$out" | grep -qx '3 4' || fail "NR,NF wrong for line 3" "$out"
# pipe input
printf '%s\n' "$(R "cat D.TXT | awk '{print \$1}'" 'awk .{print')" | grep -qx 'alpha' || fail "pipe: print \$1 missed 'alpha'"
# NR into double digits (exercises the 16-bit number printer)
printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\n' > n12.txt
python3 $ROOT/tools/p8xfs.py put awk.img n12.txt --name /N12.TXT >/dev/null
out=$(R "awk '{print NR}' N12.TXT" 'print NR')
printf '%s\n' "$out" | grep -qx '11' || fail "NR did not reach a correct 2-digit '11'" "$out"
printf '%s\n' "$out" | grep -qx '12' || fail "NR did not reach a correct 2-digit '12'" "$out"

# --- C vs hand-asm twin: identical output on the same program set ---
sh $ROOT/os/commands-asm/mkasm.sh awk > awk.a.asm
python3 $ROOT/assembler/p8xasm.py awk.a.asm -o awk.a.bin --base 0x6A00 >/dev/null
rm -f awka.img
python3 $ROOT/tools/p8xfs.py create awka.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   awka.img osawk.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  awka.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    awka.img awk.a.bin --name /bin/awk.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    awka.img cat.a2.bin --name /bin/cat.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    awka.img d.txt --name /D.TXT >/dev/null
python3 $ROOT/tools/p8xfs.py put    awka.img p.txt --name /P.TXT >/dev/null
TSEQ="B\rawk '{print \$2}' D.TXT\rawk '/foo/{print}' D.TXT\rawk '{print \$1, \$NF}' D.TXT\rawk -F: '{print \$1}' P.TXT\rawk '{print NR, NF}' D.TXT\rawk '/alpha/' D.TXT\r"
tw() { printf "$TSEQ" | ../p8xemu -l 400000000 -c "$1" eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' | sed -n '/print .2.. D/,$p'; }
tw awk.img  > twc.txt
tw awka.img > twa.txt
diff twc.txt twa.txt >/dev/null || fail "C and asm awk twins differ" "$(diff twc.txt twa.txt)"

echo "OS-AWK TEST: PASS"
