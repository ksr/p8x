#!/bin/sh
# p8cc_sizes.sh -- compile every /bin C command with the host toolchain and report
# the binary size of each: the codegen benchmark for compiler work.
#
#   sh tools/p8cc_sizes.sh              print a table + total
#   sh tools/p8cc_sizes.sh > base.txt   save a baseline
#   sh tools/p8cc_sizes.sh | diff base.txt -   compare after a compiler change
#
# Uses exactly the run.sh pipeline (clib.py //#use splice -> p8cc.py -> p8xasm.py
# --base 0x6A00) on os/commands/*.c minus the lib_*.c helpers. A command that
# fails to compile is reported as FAIL (and counted as 0) so a compiler regression
# is visible in the table, not hidden.
set -e
cd "$(dirname "$0")/.."
root=$PWD
build=$(mktemp -d)
total=0; n=0; fails=0
printf '%-10s %7s\n' "command" "bytes"
for src in os/commands/*.c; do
    base=$(basename "$src" .c)
    case "$base" in lib_*) continue;; esac
    if python3 tools/clib.py "$src" -o "$build/$base.c" >/dev/null 2>&1 \
       && python3 compiler/p8cc.py "$build/$base.c" -o "$build/$base.asm" >/dev/null 2>&1 \
       && python3 assembler/p8xasm.py "$build/$base.asm" -o "$build/$base.bin" --base 0x6A00 >/dev/null 2>&1; then
        sz=$(wc -c < "$build/$base.bin" | tr -d ' ')
        printf '%-10s %7d\n' "$base" "$sz"
        total=$((total + sz)); n=$((n + 1))
    else
        printf '%-10s %7s\n' "$base" "FAIL"
        fails=$((fails + 1))
    fi
done
printf '%-10s %7d   (%d commands%s)\n' "TOTAL" "$total" "$n" "$([ $fails -gt 0 ] && echo ", $fails FAILED" || true)"
rm -rf "$build"
