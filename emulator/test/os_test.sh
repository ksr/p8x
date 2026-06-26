#!/bin/sh
# P8X/OS boot + shell test. Builds a P8XFS image with the OS, a runnable
# program (PROG.BIN, prints "RAN" then RTS to the shell), and a data file
# (HELLO.TXT), boots it through the ROM monitor (B), then exercises the shell:
#   DIR              -> lists both files
#   RUN PROG.BIN     -> prints RAN (program loaded to $B000 and JSR'd)
#   DEL HELLO.TXT    -> marks the entry deleted and writes the sector back
#   SAVE C.BIN 4000 4010 -> create a file from memory ($4000 = the OS image)
#   DIR              -> re-read from disk: HELLO.TXT gone, PROG.BIN + C.BIN kept
# Then on the host: get C.BIN back and confirm its bytes equal p8xos.bin[0:16].
# Exercises the whole stack: assembler --base, p8xfs.py, the BIOS jump table,
# the CF model, and the OS shell / filesystem code.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o p8xos.bin --base 0x4000 >/dev/null

# A position-independent program at its load address $B000: print "RAN\r\n"
# via the BIOS CONOUT vector, then RTS back to the shell.
cat > prog.asm <<'EOF'
        .org $A700
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
python3 $ROOT/assembler/p8xasm.py prog.asm -o prog.bin --base 0xA700 >/dev/null

rm -f os.img
python3 $ROOT/tools/p8xfs.py create os.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot os.img p8xos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put os.img prog.bin --name PROG.BIN >/dev/null
# DIR is no longer a built-in — install /BIN/DIR.BIN so bare `DIR` / `DIR >DLIST`
# resolve via implicit RUN. (DUMP is still native; DEP/DUMP below are unchanged.)
python3 $ROOT/tools/clib.py $ROOT/os/commands/dir.c -o os_dir.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py os_dir.pp.c -o os_dir.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py os_dir.asm -o os_dir.bin --base 0xA700 >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir os.img /BIN >/dev/null
python3 $ROOT/tools/p8xfs.py put os.img os_dir.bin --name /BIN/DIR.BIN --load 0xA700 --exec 0xA700 >/dev/null
printf 'hi' > os_h.tmp
python3 $ROOT/tools/p8xfs.py put os.img os_h.tmp --name HELLO.TXT >/dev/null
rm -f os_h.tmp prog.asm

# DUMP B000 now pages: CR advances to the next block (B100), '.' exits — so feed
# '\r.' after the address (else PACK's letters would be eaten as paging keys).
# ...then 'DIR >DLIST' captures the directory listing into a file (output
# redirection), and EXIT returns to the monitor.
# Also: SAVE over an existing name must be rejected (?EXISTS), and a redirected
# command's error must still reach the console (DEL NOPE >X -> ?NO FILE on screen;
# built-in errors use PUTS, not the redirectable OUTCH, so they bypass redirection).
out=$(printf 'B\rDIR\rRUN PROG.BIN\rDEL HELLO.TXT\rSAVE C.BIN 4000 4010\rDEP B000 41 42 43\rDUMP B000\r\r.PACK\rFSCK\rDIR\rDIR >DLIST\rSAVE PROG.BIN 4000 4001\rDEL NOPE >X\rEXIT\r' | \
      ../p8xemu -l 80000000 -c os.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')

fail() { echo "OS TEST: FAIL — $1"; echo "$out" | sed -n '/P8X\/OS/,$p'; exit 1; }
echo "$out" | grep -q 'P8X/OS v1.0' || fail "OS did not boot"
echo "$out" | grep -q 'PROG.BIN'    || fail "DIR missing PROG.BIN"
echo "$out" | grep -q 'HELLO.TXT'   || fail "DIR missing HELLO.TXT"
echo "$out" | grep -q 'RAN'         || fail "RUN did not execute the program"
echo "$out" | grep -q 'DELETED'     || fail "DEL did not report success"
echo "$out" | grep -q 'SAVED'       || fail "SAVE did not report success"
# DEP B000 41 42 43, then DUMP B000 -> the row shows the bytes and ASCII "ABC".
echo "$out" | grep -q 'B000: 41 42 43' || fail "DEP/DUMP did not show deposited bytes"
echo "$out" | grep -q 'ABC'            || fail "DUMP ASCII column wrong"
# DUMP paging: CR after the first block advanced to the next one (rows at B100).
echo "$out" | grep -q 'B100'           || fail "DUMP paging (CR=next block) did not advance"
echo "$out" | grep -q 'PACKED'       || fail "PACK did not report success"
echo "$out" | grep -q 'FSCK OK'      || fail "FSCK reported problems on a clean v2 volume"
# After DEL+SAVE+PACK, the final DIR (re-read from disk): HELLO.TXT gone, C.BIN
# kept. (DEL HELLO left a gap that PACK reclaims by moving C.BIN down.)
tail=$(echo "$out" | sed -n '/PACKED/,$p')
echo "$tail" | grep -q 'HELLO.TXT' && fail "HELLO.TXT still listed after DEL" || true
echo "$tail" | grep -q 'PROG.BIN'  || fail "PROG.BIN lost"
echo "$tail" | grep -q 'C.BIN'     || fail "C.BIN lost after PACK"
# EXIT leaves the OS and cold-restarts the monitor: its banner shows a 2nd time
# (once for the initial B-boot, once after EXIT).
[ "$(echo "$out" | grep -c 'P8X MONITOR')" -ge 2 ] || fail "EXIT did not return to the monitor"

# Host round-trip: SAVE'd C.BIN must equal the first 16 bytes of the OS image
# (it was saved straight from $4000, where the OS image is loaded verbatim) —
# and must still match AFTER PACK relocated its extent.
python3 $ROOT/tools/p8xfs.py get os.img C.BIN --out os_c.tmp >/dev/null
head -c 16 p8xos.bin > os_exp.tmp
cmp -s os_c.tmp os_exp.tmp || fail "C.BIN bytes wrong after PACK"
rm -f os_c.tmp os_exp.tmp
# Output redirection: 'DIR >DLIST' must have created DLIST holding the captured
# directory listing (so it contains a known entry name, PROG.BIN).
python3 $ROOT/tools/p8xfs.py get os.img DLIST --out os_dl.tmp >/dev/null || fail "redirect: DLIST not created"
LC_ALL=C tr -d '\0\r' < os_dl.tmp | grep -q 'PROG.BIN' || { echo "--- DLIST ---"; cat os_dl.tmp; fail "redirect: DLIST missing captured listing"; }
rm -f os_dl.tmp
# Duplicate name rejected: SAVE PROG.BIN (already exists) -> ?EXISTS.
echo "$out" | grep -q 'EXISTS'  || fail "duplicate SAVE not rejected (?EXISTS missing)"
# stderr: a redirected command's error still prints on the console.
echo "$out" | grep -q 'NO FILE' || fail "redirected command's error did not reach the console"
# PACK must leave a consistent volume with nothing reclaimable.
python3 $ROOT/tools/p8xfs.py fsck os.img >os_fsck.tmp 2>&1 || { cat os_fsck.tmp; fail "fsck failed after PACK"; }
grep -q '0 reclaimable' os_fsck.tmp || { cat os_fsck.tmp; fail "PACK left reclaimable space"; }
rm -f os_fsck.tmp
echo "OS TEST: PASS"
