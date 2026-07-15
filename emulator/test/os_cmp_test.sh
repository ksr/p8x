#!/bin/sh
# cmp (os/commands/cmp.c): byte-for-byte file compare. Silent when identical;
# otherwise the first differing byte/line, or EOF-on-the-shorter-file.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-CMP TEST: FAIL — $1"; [ -n "$2" ] && printf '%s\n' "$2"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o oscmp.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/cmp.c -o cmp.pp.c
python3 $ROOT/compiler/p8cc.py cmp.pp.c -o cmp.t.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cmp.t.asm -o cmp.t.bin --base 0x6A00 >/dev/null
rm -f cmp.img
python3 $ROOT/tools/p8xfs.py create cmp.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cmp.img oscmp.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cmp.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cmp.img cmp.t.bin --name /bin/cmp.bin --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'hello world\nsecond line\n' > A.TXT
printf 'hello world\nsecond line\n' > B.TXT
printf 'hello worle\nsecond line\n' > C.TXT
printf 'hello world\n'              > D.TXT
for f in A B C D; do python3 $ROOT/tools/p8xfs.py put cmp.img $f.TXT --name /$f.TXT >/dev/null; done

R() { printf "B\r$1\r" | ../p8xemu -l 300000000 -c cmp.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | sed -n "/$2/,/^\/> \$/p" | grep -v '^/> ' | grep -v '^$'; }

# identical -> silent (no output line)
[ -z "$(R 'cmp A.TXT B.TXT' 'cmp A.TXT B')" ] || fail "identical files should produce no output"
# differ at byte 11, line 1
R 'cmp A.TXT C.TXT' 'cmp A.TXT C' | grep -q 'differ: byte 11, line 1' || fail "wrong first-difference report"
# file2 shorter -> EOF on file2
R 'cmp A.TXT D.TXT' 'cmp A.TXT D' | grep -q 'EOF on file2' || fail "did not report EOF on the shorter file2"
# file1 shorter -> EOF on file1
R 'cmp D.TXT A.TXT' 'cmp D.TXT A' | grep -q 'EOF on file1' || fail "did not report EOF on the shorter file1"
# a difference far enough in to need a 2-digit byte number (exercises 16-bit pnum)
printf '0123456789ABCDEFGHIJ\n' > E.TXT
printf '0123456789ABCDEFGXIJ\n' > F.TXT
python3 $ROOT/tools/p8xfs.py put cmp.img E.TXT --name /E.TXT >/dev/null
python3 $ROOT/tools/p8xfs.py put cmp.img F.TXT --name /F.TXT >/dev/null
R 'cmp E.TXT F.TXT' 'cmp E.TXT F' | grep -q 'byte 18, line 1' || fail "2-digit byte offset wrong"

# --- C vs hand-asm twin: identical output ---
sh $ROOT/os/commands-asm/mkasm.sh cmp > cmp.a.asm
python3 $ROOT/assembler/p8xasm.py cmp.a.asm -o cmp.a.bin --base 0x6A00 >/dev/null
rm -f cmpa.img
python3 $ROOT/tools/p8xfs.py create cmpa.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cmpa.img oscmp.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cmpa.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cmpa.img cmp.a.bin --name /bin/cmp.bin --load 0x6A00 --exec 0x6A00 >/dev/null
for f in A B C D E F; do python3 $ROOT/tools/p8xfs.py put cmpa.img $f.TXT --name /$f.TXT >/dev/null; done
TSEQ='B\rcmp A.TXT B.TXT\rcmp A.TXT C.TXT\rcmp A.TXT D.TXT\rcmp D.TXT A.TXT\rcmp E.TXT F.TXT\r'
tw() { printf "$TSEQ" | ../p8xemu -l 300000000 -c "$1" eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' | sed -n '/cmp A.TXT B/,$p'; }
tw cmp.img > cmpc.txt
tw cmpa.img > cmpaa.txt
diff cmpc.txt cmpaa.txt >/dev/null || fail "C and asm cmp twins differ" "$(diff cmpc.txt cmpaa.txt)"

echo "OS-CMP TEST: PASS"
