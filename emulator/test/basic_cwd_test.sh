#!/bin/sh
# BASIC honours the OS current directory for SAVE/LOAD.
#
# Regression for: from the OS shell, `cd src` then `basic` then SAVE "T" used to
# write /T, not /src/T. The BIOS resolvers (FRESOLVE/FOPEN/FOPENDIR) always start
# at the ROOT; /bin commands prefix the CWD first (lib_apath.c abspath), and BASIC
# did not because it made no OS calls at all. APATH in p8xbasic.asm is that step.
#
# Checks three things, because the first alone would pass with a broken absolute
# path and the second alone would pass if APATH simply prefixed everything:
#   1. a relative SAVE from a subdirectory lands in that subdirectory
#   2. it does NOT also land in the root
#   3. an ABSOLUTE path still works from a different directory (the early-out)
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$(dirname "$0")"
fail() { echo "BASIC-CWD TEST: FAIL — $1"; exit 1; }

python3 "$ROOT/assembler/p8xasm.py" "$ROOT/basic/p8xbasic.asm" -o bcwd.bin --base 0x6A00 \
    -D BASORG=0x6A00 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x2000 >/dev/null \
    || fail "BASIC (TPA build) did not assemble"

# A disk with the OS, a subdirectory, and this BASIC build. Installed under a
# fresh name because p8xfs put does not replace an existing file -- which is
# exactly what made an earlier run of this fix look broken.
cp "$ROOT/os/run-disk.img" bcwd.img 2>/dev/null || fail "need os/run-disk.img (run os/run.sh once)"
python3 "$ROOT/tools/p8xfs.py" put bcwd.img bcwd.bin --name /bin/bcwd.bin \
    --load 0x6A00 --exec 0x6A00 >/dev/null || fail "could not install the test BASIC"

printf 'B\rcd src\rbcwd\r10 PRINT "C"\rSAVE "CWDT"\rBYE\rcd /\rbcwd\rLOAD "/src/CWDT"\rLIST\rBYE\r' \
    > bcwd.in
../p8xemu -N -i bcwd.in -c bcwd.img -l 60000000 eeprom.bin > bcwd.out 2>/dev/null || true

python3 "$ROOT/tools/p8xfs.py" ls bcwd.img /src 2>/dev/null | grep -qi "CWDT" \
    || fail "SAVE from /src did not create /src/CWDT (still resolving from the root?)"
python3 "$ROOT/tools/p8xfs.py" ls bcwd.img 2>/dev/null | grep -qi "CWDT" \
    && fail "SAVE from /src ALSO wrote /CWDT — the path was not made relative to the CWD"
grep -q 'PRINT "C"' bcwd.out \
    || fail "LOAD of the absolute path /src/CWDT did not return the program"

echo "BASIC-CWD TEST: PASS"
