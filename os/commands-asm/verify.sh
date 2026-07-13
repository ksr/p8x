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
$ASM "$ROOT/os/p8xos.asm" -o "$W/osc.bin" --base 0x2000 >/dev/null

# fixtures $1=img : a small tree both builds see (command binary added by caller)
fixtures() {
    $FS create "$1" >/dev/null
    $FS boot   "$1" "$W/osc.bin" >/dev/null
    $FS mkdir  "$1" /bin >/dev/null
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
    printf 'deep\r\n' > "$W/z.dat"; $FS put "$1" "$W/z.dat" --name /SUB/DEEP/ZREL.TXT >/dev/null
    $FS mkdir "$1" /man >/dev/null
    printf 'DIR(1)\r\nNAME\r\n  dir - list directory contents\r\n' > "$W/mdir.dat"
    $FS put "$1" "$W/mdir.dat" --name /man/dir >/dev/null
}

# cmd_script $1=CMD(upper) : echo the \r-separated shell lines for that command
cmd_script() {
    case "$1" in
        PWD)  printf 'cd /SUB\rpwd\r' ;;
        # a FIXED memory range (the ROM BIOS jump table) so both builds decode the
        # same bytes — the program itself loads at $6A00 and would differ.
        DISASM) printf 'disasm 0100 0140\r' ;;
        # -R targets /SUB (no .bin files): a recursive listing of /bin would
        # show dir.bin's own byte size, which legitimately differs between the
        # p8cc and asm builds — a size artifact, not a behavior difference.
        # `cd /SUB; dir DEEP` exercises a RELATIVE path arg (must resolve vs the
        # CWD -> /SUB/DEEP, not /DEEP): the two builds must agree on it too.
        DIR)  printf 'dir\rdir -S\rdir /SUB\rcd /SUB\rdir DEEP\rcd /\rdir *.LOG\rdir -R /SUB\rdir -R -S /SUB\rdir /NOPE\r' ;;
        TREE) printf 'tree\r' ;;
        MV)   printf 'mv T.TXT R.TXT\rcat R.TXT\rmv *.LOG SUB\rfind LOG\rmv *.LOG NOPE\rmv R.TXT R.TXT\r' ;;
        WC)   printf 'wc T.TXT\rwc *.LOG\rcat T.TXT | wc\rwc -h\r' ;;
        HEAD) printf 'head N.TXT\rhead -3 N.TXT\rhead -h\r' ;;
        TAIL) printf 'tail N.TXT\rtail -3 N.TXT\r' ;;
        UNIQ) printf 'uniq U.TXT\r' ;;
        CAT)  printf 'cat T.TXT\rcat *.LOG\rcat NOPE.TXT\r' ;;
        MORE) printf 'more N.TXT\rmore BIG.TXT\rq\rmore -h\r' ;;
        FIND) printf 'find .TXT\rfind *.LOG\rfind SUB\rfind -h\r' ;;
        SORT) printf 'sort S.TXT\rsort *.LOG\rsort -h\r' ;;
        CP)   printf 'cp T.TXT C.TXT\rcat C.TXT\rcp -r SUB S2\rfind S2\rcp *.LOG SUB\rfind LOG\rcp *.LOG T.TXT\rcp X X\r' ;;
        GREP) printf 'grep alpha T.TXT\rgrep ^beta T.TXT\rgrep al.ha T.TXT\rgrep mm+ T.TXT\rgrep -r alpha\rgrep x NOPE\rgrep -h\r' ;;
        SED)  printf 'sed s/alpha/X/ T.TXT\rsed s/l/L/g T.TXT\rsed -h\r' ;;
        DIFF) printf 'diff T.TXT U.TXT\rdiff T.TXT T.TXT\rdiff -h\r' ;;
        VI)   printf 'vi N.TXT\rxjA!\033:wq\rcat N.TXT\rvi -h\r' ;;
        # create a missing file, then touch an existing one and confirm it is
        # NOT truncated (cat still shows its content). find/cat are helpers.
        TOUCH) printf 'touch NEW.TXT\rfind NEW\rtouch T.TXT\rcat T.TXT\rtouch -h\r' ;;
        MAN)  printf 'man dir\rman nope\rman -h\r' ;;
        # dep is quiet on success (both builds); usage/bad-addr paths print.
        DEP)  printf 'dep -h\rdep\rdep zz\rdep 9000 41 42 43\r' ;;
        # dump a zeroed RAM page clear of the program at $6A00 (identical in
        # both builds); '.' exits the pager; then the usage/bad-addr paths.
        DUMP) printf 'dump 9000\r.\rdump -h\rdump zz\r' ;;
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
    $ASM "$W/$1.hlp.asm" -o "$W/$1_h.bin" --base 0x6A00 >/dev/null 2>&1
}
build_c cat; build_c find
install_helpers() { # $1=img  $2=name-under-test (lowercase, skip that one)
    for h in cat find; do
        [ "$h" = "$2" ] && continue
        $FS put "$1" "$W/${h}_h.bin" --name "/bin/$h.bin" --load 0x6A00 --exec 0x6A00 >/dev/null
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
    $ASM "$W/${cmd}_c.asm" -o "$W/${cmd}_c.bin" --base 0x6A00 >/dev/null 2>&1
    sh "$ADIR/mkasm.sh" "$cmd" > "$W/${cmd}_full.asm"
    $ASM "$W/${cmd}_full.asm" -o "$W/${cmd}_a.bin" --base 0x6A00 >/dev/null 2>&1
    scr=$(cmd_script "$up")
    fixtures "$W/dc.img"; install_helpers "$W/dc.img" "$cmd"; $FS put "$W/dc.img" "$W/${cmd}_c.bin" --name "/bin/$cmd.bin" --load 0x6A00 --exec 0x6A00 >/dev/null
    fixtures "$W/da.img"; install_helpers "$W/da.img" "$cmd"; $FS put "$W/da.img" "$W/${cmd}_a.bin" --name "/bin/$cmd.bin" --load 0x6A00 --exec 0x6A00 >/dev/null
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
