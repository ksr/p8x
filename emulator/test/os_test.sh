#!/bin/sh
# P8X/OS boot + shell test. Builds a P8XFS image with the OS, a runnable
# program (PROG.bin, prints "RAN" then RTS to the shell), and a data file
# (HELLO.TXT), boots it through the ROM monitor (B), then exercises the shell:
#   DIR              -> lists both files
#   RUN PROG.bin     -> prints RAN (program loaded to $B000 and JSR'd)
#   DEL HELLO.TXT    -> marks the entry deleted and writes the sector back
#   SAVE C.bin 2000 2010 -> create a file from memory ($2000 = the OS image)
#   DIR              -> re-read from disk: HELLO.TXT gone, PROG.bin + C.bin kept
# Then on the host: get C.bin back and confirm its bytes equal p8xos.bin[0:16].
# Exercises the whole stack: assembler --base, p8xfs.py, the BIOS jump table,
# the CF model, and the OS shell / filesystem code.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o p8xos.bin --base 0x2000 >/dev/null

# A position-independent program at its load address $B000: print "RAN\r\n"
# via the BIOS CONOUT vector, then RTS back to the shell.
cat > prog.asm <<'EOF'
        .org $7A00
        LDA  #'R'
        JSR  $0103
        LDA  #'A'
        JSR  $0103
        LDA  #'N'
        JSR  $0103
        LDA  #$0D
        JSR  $0103
        LDA  #$0A
        JSR  $0103
        RTS
EOF
python3 $ROOT/assembler/p8xasm.py prog.asm -o prog.bin --base 0x7A00 >/dev/null

rm -f os.img
python3 $ROOT/tools/p8xfs.py create os.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot os.img p8xos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put os.img prog.bin --name PROG.bin >/dev/null
# DIR is no longer a built-in — install /bin/dir.bin so bare `DIR` / `DIR >DLIST`
# resolve via implicit RUN. (DUMP/DEP are now /bin programs too — covered by
# os_depdump_test.sh, so this smoke test no longer exercises them.)
python3 $ROOT/tools/clib.py $ROOT/os/commands/dir.c -o os_dir.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py os_dir.pp.c -o os_dir.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py os_dir.asm -o os_dir.bin --base 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir os.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put os.img os_dir.bin --name /bin/dir.bin --load 0x7A00 --exec 0x7A00 >/dev/null
printf 'hi' > os_h.tmp
python3 $ROOT/tools/p8xfs.py put os.img os_h.tmp --name HELLO.TXT >/dev/null
rm -f os_h.tmp prog.asm

# 'DIR >DLIST' captures the directory listing into a file (output redirection),
# and EXIT returns to the monitor.
# Also: SAVE over an existing name must be rejected (?EXISTS), and a redirected
# command's error must still reach the console (DEL NOPE >X -> ?NO FILE on screen;
# built-in errors use PUTS, not the redirectable OUTCH, so they bypass redirection).
out=$(printf 'B\rdir\rrun PROG.bin\rdel HELLO.TXT\rsave C.bin 2000 2010\rpack\rfsck\rdir\rdir >DLIST\rsave PROG.bin 2000 2001\rdel NOPE >X\rexit\r' | \
      ../p8xemu -l 80000000 -c os.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')

fail() { echo "OS TEST: FAIL — $1"; echo "$out" | sed -n '/P8X\/OS/,$p'; exit 1; }
echo "$out" | grep -q 'P8X/OS v1.0' || fail "OS did not boot"
echo "$out" | grep -q 'PROG.bin'    || fail "DIR missing PROG.bin"
echo "$out" | grep -q 'HELLO.TXT'   || fail "DIR missing HELLO.TXT"
echo "$out" | grep -q 'RAN'         || fail "RUN did not execute the program"
echo "$out" | grep -q 'DELETED'     || fail "DEL did not report success"
echo "$out" | grep -q 'SAVED'       || fail "SAVE did not report success"
echo "$out" | grep -q 'PACKED'       || fail "PACK did not report success"
echo "$out" | grep -q 'FSCK OK'      || fail "FSCK reported problems on a clean v2 volume"
# After DEL+SAVE+PACK, the final DIR (re-read from disk): HELLO.TXT gone, C.bin
# kept. (DEL HELLO left a gap that PACK reclaims by moving C.bin down.)
tail=$(echo "$out" | sed -n '/PACKED/,$p')
echo "$tail" | grep -q 'HELLO.TXT' && fail "HELLO.TXT still listed after DEL" || true
echo "$tail" | grep -q 'PROG.bin'  || fail "PROG.bin lost"
echo "$tail" | grep -q 'C.bin'     || fail "C.bin lost after PACK"
# EXIT leaves the OS and cold-restarts the monitor: its banner shows a 2nd time
# (once for the initial B-boot, once after EXIT).
[ "$(echo "$out" | grep -c 'P8X MONITOR')" -ge 2 ] || fail "EXIT did not return to the monitor"

# Host round-trip: SAVE'd C.bin must equal the first 16 bytes of the OS image
# (it was saved straight from $2000, where the OS image is loaded verbatim) —
# and must still match AFTER PACK relocated its extent.
python3 $ROOT/tools/p8xfs.py get os.img C.bin --out os_c.tmp >/dev/null
head -c 16 p8xos.bin > os_exp.tmp
cmp -s os_c.tmp os_exp.tmp || fail "C.bin bytes wrong after PACK"
rm -f os_c.tmp os_exp.tmp
# Output redirection: 'DIR >DLIST' must have created DLIST holding the captured
# directory listing (so it contains a known entry name, PROG.bin).
python3 $ROOT/tools/p8xfs.py get os.img DLIST --out os_dl.tmp >/dev/null || fail "redirect: DLIST not created"
LC_ALL=C tr -d '\0\r' < os_dl.tmp | grep -q 'PROG.bin' || { echo "--- DLIST ---"; cat os_dl.tmp; fail "redirect: DLIST missing captured listing"; }
rm -f os_dl.tmp
# Duplicate name rejected: SAVE PROG.bin (already exists) -> ?EXISTS.
echo "$out" | grep -q 'EXISTS'  || fail "duplicate SAVE not rejected (?EXISTS missing)"
# stderr: a redirected command's error still prints on the console.
echo "$out" | grep -q 'NO FILE' || fail "redirected command's error did not reach the console"
# PACK must leave a consistent volume with nothing reclaimable.
python3 $ROOT/tools/p8xfs.py fsck os.img >os_fsck.tmp 2>&1 || { cat os_fsck.tmp; fail "fsck failed after PACK"; }
grep -q '0 reclaimable' os_fsck.tmp || { cat os_fsck.tmp; fail "PACK left reclaimable space"; }
rm -f os_fsck.tmp
echo "OS TEST: PASS"
