#!/bin/sh
# FULL SYSTEM BUILD TEST — build the entire ready-to-boot system the way os/run.sh
# does (monitor + OS + microcode + emulator + a P8XFS v2 disk carrying every /bin
# C command, the hand-asm twins (now the /bin default; C in /binc), /man pages, /lib helpers, the /src source
# tree with per-directory Makefiles, and a 2nd data volume), then boot it headless
# and smoke-test the whole stack end to end:
#   - boots P8X/OS from the built image
#   - PATH + userland: `dir /bin` lists compiled commands
#   - pipes + redirection: `cat README.TXT | grep hello` (2-stage pipe)
#   - the native toolchain: `cd /src/commands/c && make pwd` rebuilds pwd (and the
#     asm twin) on-target via the `make` built-in, and the freshly built binary RUNs
#   - dual CompactFlash: the 2nd card is mounted at /d1 and readable
# This is the slow, comprehensive build check; run on demand.
set -e
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)          # absolute — we cd into the build dir later
fail() { echo "SYSBUILD TEST: FAIL — $1"; exit 1; }

work=$(mktemp -d)
D0="$work/d0.img"; D1="$work/d1.img"
# Build the full system headless (this compiles the emulator + assembles + lays
# down the complete disk tree; no interactive session).
P8X_BUILD_ONLY=1 sh "$ROOT/os/run.sh" "$D0" "$D1" >"$work/build.log" 2>&1 \
    || { tail -20 "$work/build.log"; fail "run.sh build-only failed"; }
[ -f "$work/p8xemu" ] && [ -f "$work/eeprom.bin" ] || fail "build did not produce emulator/eeprom"

# sanity: the image really carries the expected trees
$ROOT/tools/p8xfs.py ls "$D0" /bin 2>/dev/null | grep -qE '^cat\.bin '  || fail "/bin/cat.bin missing from the built disk"
$ROOT/tools/p8xfs.py ls "$D0" /src/commands/c 2>/dev/null | grep -qE '^Makefile ' || fail "/src/commands/c/Makefile missing"
$ROOT/tools/p8xfs.py ls "$D0" /src/commands/c 2>/dev/null | grep -qE '^pwd\.c ' || fail "/src sources missing"

# Boot headless and drive a smoke session.
cd "$work"
# Rebuild a command ON THE EMULATOR with `make` (both the C and asm twins) and RUN
# the freshly built C binary — proving the whole native toolchain (sh -> cc ->
# asm, plus the asm ;#use) works end to end on the built system. A COMPLETE
# on-emulator rebuild of all 42 commands is `make` (or `sh /src/mk/all.sh`) on-target;
# A COMPLETE on-emulator rebuild of all 42 commands is `cd /src/commands/c && make
# all` (and the asm dir) on-target; the automated test rebuilds one here because each
# cc+asm is millions of emulated cycles — a full sweep is minutes of wall time, so
# it's driven manually, not in CI.
printf 'B\rdir /bin\rcat README.TXT | grep hello\rcd /src/commands/c\rmake pwd\rcd /src/commands/asm\rmake pwd\rcd /\rrun /src/commands/c/bin/pwd.bin\rcat /d1/DATA/NOTES.TXT\r' \
    | ./p8xemu -l 9000000000 -c "$D0" -c2 "$D1" eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > sys_out.txt

grep -q 'P8X/OS' sys_out.txt                 || fail "did not boot P8X/OS"
grep -qE 'cat\.bin'  sys_out.txt             || fail "dir /bin did not list the compiled commands"
grep -qi 'hello from P8X' sys_out.txt        || fail "cat | grep pipe did not pass 'hello' through"
$ROOT/tools/p8xfs.py ls "$D0" /src/commands/c/bin   2>/dev/null | grep -qE '^pwd\.bin ' || fail "make pwd (C): no C binary"
$ROOT/tools/p8xfs.py ls "$D0" /src/commands/asm/bin 2>/dev/null | grep -qE '^pwd\.bin ' || fail "make pwd (asm): no asm binary"
grep -qE '^/$' sys_out.txt                   || fail "rebuilt pwd.bin did not run / print the CWD"
grep -q 'drive 1' sys_out.txt                || fail "/d1/DATA/NOTES.TXT (dual-CF mount) not readable"

echo "SYSBUILD TEST: PASS"
