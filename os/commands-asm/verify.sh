#!/bin/sh
# verify.sh — prove each hand-asm command behaves byte-identically to its p8cc
# twin. For every command that has BOTH os/commands/NAME.c and
# os/commands-asm/NAME.asm, build both binaries, install each in turn as
# /BIN/<NAME>.BIN on a freshly-built fixture disk, drive the SAME shell script
# through the emulator, and diff the two transcripts. Any difference = FAIL.
#
#     sh os/commands-asm/verify.sh [cmd ...]     # default: all ported commands
#
# The per-command shell scripts live in cmd_script(); fixtures() lays down a
# small tree both builds see identically. A fresh disk per run means mutating
# commands (mv) compare cleanly.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
CDIR="$ROOT/os/commands"; ADIR="$HERE"
W="$HERE/.verify"; mkdir -p "$W"
UC="$ROOT/microcode"
ASM="python3 $ROOT/assembler/p8xasm.py"
CC="python3 $ROOT/compiler/p8cc.py"
CLIB="python3 $ROOT/tools/clib.py"
FS="python3 $ROOT/tools/p8xfs.py"

cp "$UC"/u?.bin "$W"/ 2>/dev/null
$ASM "$ROOT/firmware/p8xmon.asm" -o "$W/eeprom.bin" >/dev/null
$ASM "$ROOT/os/p8xos.asm" -o "$W/osc.bin" --base 0x4000 >/dev/null

# fixtures $1=img : a small tree both builds see (command binary added by caller)
fixtures() {
    $FS create "$1" >/dev/null
    $FS boot   "$1" "$W/osc.bin" >/dev/null
    $FS mkdir  "$1" /BIN >/dev/null
    $FS mkdir  "$1" /SUB >/dev/null
    printf 'alpha\r\nbeta\r\ngamma alpha\r\n'      > "$W/t.dat"; $FS put "$1" "$W/t.dat" --name T.TXT >/dev/null
    printf 'one\r\none\r\ntwo\r\ntwo\r\ntwo\r\none\r\n' > "$W/u.dat"; $FS put "$1" "$W/u.dat" --name U.TXT >/dev/null
    printf 'l1\r\nl2\r\nl3\r\nl4\r\nl5\r\nl6\r\nl7\r\nl8\r\nl9\r\nl10\r\nl11\r\nl12\r\n' > "$W/n.dat"
    $FS put "$1" "$W/n.dat" --name N.TXT >/dev/null
    i=1; : > "$W/big.dat"; while [ $i -le 30 ]; do printf 'line%d\r\n' $i >> "$W/big.dat"; i=$((i+1)); done
    $FS put "$1" "$W/big.dat" --name BIG.TXT >/dev/null
    printf 'pear\r\napple\r\ncherry\r\napple\r\nbanana\r\n' > "$W/s.dat"; $FS put "$1" "$W/s.dat" --name S.TXT >/dev/null
    printf 'red\r\nblue\r\n' > "$W/g1.dat"; $FS put "$1" "$W/g1.dat" --name G1.LOG >/dev/null
    printf 'green\r\n'       > "$W/g2.dat"; $FS put "$1" "$W/g2.dat" --name G2.LOG >/dev/null
    $FS mkdir "$1" /SUB/DEEP >/dev/null
    printf 'x\r\n' > "$W/m.dat"; $FS put "$1" "$W/m.dat" --name /SUB/M.TXT >/dev/null
}

# cmd_script $1=CMD(upper) : echo the \r-separated shell lines for that command
cmd_script() {
    case "$1" in
        PWD)  printf 'CD /SUB\rPWD\r' ;;
        # -R targets /SUB (no .BIN files): a recursive listing of /BIN would
        # show DIR.BIN's own byte size, which legitimately differs between the
        # p8cc and asm builds — a size artifact, not a behavior difference.
        DIR)  printf 'DIR\rDIR /SUB\rDIR *.LOG\rDIR -R /SUB\rDIR /NOPE\r' ;;
        TREE) printf 'TREE\r' ;;
        MV)   printf 'MV T.TXT R.TXT\rDIR\rCAT R.TXT\rMV R.TXT R.TXT\r' ;;
        WC)   printf 'WC T.TXT\rWC *.LOG\rCAT T.TXT | WC\rWC -h\r' ;;
        HEAD) printf 'HEAD N.TXT\rHEAD -3 N.TXT\rHEAD -h\r' ;;
        TAIL) printf 'TAIL N.TXT\rTAIL -3 N.TXT\r' ;;
        UNIQ) printf 'UNIQ U.TXT\r' ;;
        CAT)  printf 'CAT T.TXT\rCAT *.LOG\rCAT NOPE.TXT\r' ;;
        MORE) printf 'MORE N.TXT\rMORE BIG.TXT\rq\rMORE -h\r' ;;
        FIND) printf 'FIND .TXT\rFIND *.LOG\rFIND SUB\rFIND -h\r' ;;
        SORT) printf 'SORT S.TXT\rSORT *.LOG\rSORT -h\r' ;;
        CP)   printf 'CP T.TXT C.TXT\rCAT C.TXT\rCP -r SUB S2\rFIND S2\rCP X X\r' ;;
        GREP) printf 'GREP alpha T.TXT\rGREP ^beta T.TXT\rGREP al.ha T.TXT\rGREP mm+ T.TXT\rGREP -r alpha\rGREP x NOPE\rGREP -h\r' ;;
        SED)  printf 'SED s/alpha/X/ T.TXT\rSED s/l/L/g T.TXT\rSED -h\r' ;;
        DIFF) printf 'DIFF T.TXT U.TXT\rDIFF T.TXT T.TXT\rDIFF -h\r' ;;
        VI)   printf 'VI N.TXT\rxjA!\033:wq\rCAT N.TXT\rVI -h\r' ;;
    esac
}

run() { # $1=img $2=script -> transcript
    # The emulator loads microcode u?.bin from the CWD, so run from $W (which has
    # them copied in above). $1 is absolute, eeprom.bin is in $W.
    ( cd "$W" && printf 'B\r%s' "$2" | "$ROOT/emulator/p8xemu" -l 400000000 -c "$1" eeprom.bin 2>/dev/null ) | LC_ALL=C tr -d '\0\r'
}

# Build C helper commands (cat, find) once — installed on every disk so tests of
# mutating commands (cp, mv) can inspect results by content. Same build on both
# disks, so they don't affect the c-vs-a comparison.
build_c() { # $1=name -> $W/<name>_h.bin
    $CLIB "$CDIR/$1.c" -o "$W/$1.hpp.c" 2>/dev/null
    $CC "$W/$1.hpp.c" -o "$W/$1.hlp.asm" >/dev/null 2>&1
    $ASM "$W/$1.hlp.asm" -o "$W/$1_h.bin" --base 0x7A00 >/dev/null 2>&1
}
build_c cat; build_c find
install_helpers() { # $1=img  $2=name-under-test(upper, skip that one)
    for h in CAT FIND; do
        [ "$h" = "$2" ] && continue
        l=$(echo "$h" | tr A-Z a-z)
        $FS put "$1" "$W/${l}_h.bin" --name "/BIN/$h.BIN" --load 0x7A00 --exec 0x7A00 >/dev/null
    done
}

ALL="${*:-}"
[ -z "$ALL" ] && for f in "$ADIR"/*.asm; do ALL="$ALL $(basename "$f" .asm)"; done

fails=0; ran=0
for cmd in $ALL; do
    [ -f "$CDIR/$cmd.c" ] || { echo "SKIP $cmd (no .c)"; continue; }
    [ -f "$ADIR/$cmd.asm" ] || { echo "SKIP $cmd (no .asm)"; continue; }
    up=$(echo "$cmd" | tr a-z A-Z)
    $CLIB "$CDIR/$cmd.c" -o "$W/$cmd.pp.c" 2>/dev/null
    $CC "$W/$cmd.pp.c" -o "$W/${cmd}_c.asm" >/dev/null 2>&1
    $ASM "$W/${cmd}_c.asm" -o "$W/${cmd}_c.bin" --base 0x7A00 >/dev/null 2>&1
    sh "$ADIR/mkasm.sh" "$cmd" > "$W/${cmd}_full.asm"
    $ASM "$W/${cmd}_full.asm" -o "$W/${cmd}_a.bin" --base 0x7A00 >/dev/null 2>&1
    scr=$(cmd_script "$up")
    fixtures "$W/dc.img"; install_helpers "$W/dc.img" "$up"; $FS put "$W/dc.img" "$W/${cmd}_c.bin" --name "/BIN/$up.BIN" --load 0x7A00 --exec 0x7A00 >/dev/null
    fixtures "$W/da.img"; install_helpers "$W/da.img" "$up"; $FS put "$W/da.img" "$W/${cmd}_a.bin" --name "/BIN/$up.BIN" --load 0x7A00 --exec 0x7A00 >/dev/null
    run "$W/dc.img" "$scr" > "$W/$cmd.c.out"
    run "$W/da.img" "$scr" > "$W/$cmd.a.out"
    ran=$((ran + 1))
    if diff -q "$W/$cmd.c.out" "$W/$cmd.a.out" >/dev/null; then
        echo "PASS $cmd"
    else
        echo "FAIL $cmd — output differs:"; diff "$W/$cmd.c.out" "$W/$cmd.a.out" | head -30
        fails=$((fails + 1))
    fi
done
echo "-----"; echo "$ran compared, $fails failed"
[ "$fails" -eq 0 ]
