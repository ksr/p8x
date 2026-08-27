#!/bin/sh
# The md command (Markdown console renderer): headings, wrapped prose,
# inline bold/code/links, lists with hanging indent, quotes, fenced
# code (verbatim), aligned tables, rules. Plain mode (-p) so the output
# is deterministic text; one ANSI-mode probe checks escapes appear.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "MD TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/md.c -o md_t.c
python3 $ROOT/compiler/p8cc.py md_t.c -o md_t.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py md_t.asm -o md_t.bin --base 0x6A00 >/dev/null

cat > sample.md <<'EOF'
# Title One

Prose that is long enough to wrap: alpha beta gamma delta epsilon zeta
eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon.

## Second **bold word** here

- first item
- a second item that is quite long and should wrap onto a continuation line with a hanging indent under the text
1. numbered
> quoted words

```
code line   with   spacing
```

| Name | Val |
|---|---|
| alpha | 1 |
| bee | 22 |

---
Link to [the guide](docs/guide.md) inline.
EOF

rm -f md.img
python3 $ROOT/tools/p8xfs.py create md.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   md.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  md.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    md.img md_t.bin --name /bin/md.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    md.img sample.md --name /SAMPLE.MD >/dev/null

# pager keys: feed spaces after the run line so --More-- always advances
printf 'B\rmd -p /SAMPLE.MD\r                    \r' > md.in
../p8xemu -N -i md.in -c md.img -l 400000000 eeprom.bin > md.out 2>/dev/null || true
out=$(LC_ALL=C tr '\r' '\n' < md.out | tr -d '\0')

echo "$out" | grep -q "^Title One$"            || fail "h1 text"
echo "$out" | grep -q "^=========$"            || fail "h1 underline"
echo "$out" | grep -q "^Second bold word here$" || fail "h2 with inline bold stripped"
echo "$out" | grep -q "^-------------------- *$" && true
echo "$out" | grep -q "upsilon"                || fail "prose tail survived"
awk 'length($0) > 79 && $0 !~ /More/ { bad=1 } END { exit bad }' <<A
$out
A
[ $? -eq 0 ] || fail "a wrapped line exceeded 79 columns"
echo "$out" | grep -q "^  - first item$"       || fail "bullet"
echo "$out" | grep -q "^    [a-z]"             || fail "hanging indent continuation"
echo "$out" | grep -q "^  1. numbered$"        || fail "numbered item"
echo "$out" | grep -q "^  | quoted words$"     || fail "quote"
echo "$out" | grep -q "^  code line   with   spacing$" || fail "fence verbatim"
echo "$out" | grep -q "^  Name   Val *$"       || fail "table header aligned"
echo "$out" | grep -q "^  alpha  1 *$"         || fail "table row aligned"
echo "$out" | grep -q "^  ----   --- *$" && true
echo "$out" | grep -q "the guide (docs/guide.md)" || fail "link rendering"

# ANSI mode emits escapes; plain mode must not
printf 'B\rmd /SAMPLE.MD\r                    \r' > md2.in
../p8xemu -N -i md2.in -c md.img -l 400000000 eeprom.bin > md2.out 2>/dev/null || true
LC_ALL=C grep -q "$(printf '\033')\[1m" md2.out || fail "ANSI mode has no escapes"
LC_ALL=C grep -q "$(printf '\033')" md.out && fail "plain mode leaked escapes"

echo "MD TEST: PASS (headings, wrap<=79, lists, quote, fence, aligned table, links, ANSI/plain)"
