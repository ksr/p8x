#!/bin/sh
# FULL SYSTEM BUILD TEST — build the entire ready-to-boot system the way os/run.sh
# does (monitor + OS + microcode + emulator + a P8XFS v2 disk carrying every /bin
# C command, the /bina hand-asm twins, /man pages, /lib helpers, the /src source
# tree, the /src/mk build scripts, and a 2nd data volume), then boot it headless
# and smoke-test the whole stack end to end:
#   - boots P8X/OS from the built image
#   - PATH + userland: `dir /bin` lists compiled commands
#   - pipes + redirection: `cat README.TXT | grep hello` (2-stage pipe)
#   - the native toolchain + make: `make pwd` rebuilds pwd (C + asm) on-target,
#     and the freshly built binary RUNs
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
$ROOT/tools/p8xfs.py ls "$D0" /src/mk 2>/dev/null | grep -qE '^pwd '     || fail "/src/mk/pwd (make script) missing"
$ROOT/tools/p8xfs.py ls "$D0" /src/commands/c 2>/dev/null | grep -qE '^pwd\.c ' || fail "/src sources missing"

# Boot headless and drive a smoke session.
cd "$work"
printf 'B\rdir /bin\rcat README.TXT | grep hello\rmake pwd\rrun /src/commands/c/bin/pwd.bin\rcat /d1/DATA/NOTES.TXT\r' \
    | ./p8xemu -l 2000000000 -c "$D0" -c2 "$D1" eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > sys_out.txt

grep -q 'P8X/OS' sys_out.txt                 || fail "did not boot P8X/OS"
grep -qE 'cat\.bin'  sys_out.txt             || fail "dir /bin did not list the compiled commands"
grep -qi 'hello from P8X' sys_out.txt        || fail "cat | grep pipe did not pass 'hello' through"
$ROOT/tools/p8xfs.py ls "$D0" /src/commands/c/bin   2>/dev/null | grep -qE '^pwd\.bin ' || fail "make pwd did not rebuild the C binary"
$ROOT/tools/p8xfs.py ls "$D0" /src/commands/asm/bin 2>/dev/null | grep -qE '^pwd\.bin ' || fail "make pwd did not rebuild the asm binary"
grep -q 'drive 1' sys_out.txt                || fail "/d1/DATA/NOTES.TXT (dual-CF mount) not readable"

echo "SYSBUILD TEST: PASS"
