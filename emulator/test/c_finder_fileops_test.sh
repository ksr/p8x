#!/bin/sh
# P4 Finder file operations: the FILE menu (press 'f') + rename / duplicate /
# move / new-folder / delete. Each op is delegated to the shell command that
# does the job (mv/cp/del/rmdir/mkdir) through the Finder's script-and-return
# chain, so the op runs and the Finder re-launches showing the result.
#
# Drives the real dialogs over the scripted console (typed names, ENTER/ESC),
# then checks the FILESYSTEM on the image afterwards -- the emulator persists
# CF writes to the -c image, so p8xfs ls sees what the ops did.
#
# Selection is deterministic: fscan lists ".." first, then entries in on-disk
# (creation) order. The disk is built so the lone test file /Z.TXT is the last
# root entry -- ".." , "bin", "FONT.GL", "Z.TXT" -- so three Downs select it.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
DOWN='\033[B'

fail() { echo "C-FINDER-FILEOPS TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o fos.bin --base 0x2000 >/dev/null
build() {  # compile a C command to bin/<name>
    python3 $ROOT/tools/clib.py $ROOT/os/commands/$1.c -o $1.pp.c >/dev/null
    python3 $ROOT/compiler/p8cc.py $1.pp.c -o $1.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py $1.asm -o $1.bin --base 0x6A00 >/dev/null
}
build finder; build del; build mv; build cp

# a fresh disk: /bin/{finder,del,mv,cp}.bin, /FONT.GL, and the single file /Z.TXT
mkdisk() {
    rm -f fo.img
    python3 $ROOT/tools/p8xfs.py create fo.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   fo.img fos.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  fo.img /bin >/dev/null
    for c in finder del mv cp; do
        python3 $ROOT/tools/p8xfs.py put fo.img $c.bin --name /bin/$c.bin --load 0x6A00 --exec 0x6A00 >/dev/null
    done
    python3 $ROOT/tools/p8xfs.py put fo.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null
    printf 'hello finder\n' > z.dat
    python3 $ROOT/tools/p8xfs.py put fo.img z.dat --name /Z.TXT >/dev/null
}
ls_root() { python3 $ROOT/tools/p8xfs.py ls fo.img / 2>/dev/null | awk '{print $1}'; }

# ---- new folder: f n TESTDIR ENTER (no selection needed) -------------------
mkdisk
printf "B\rrun /bin/finder.bin\rfnTESTDIR\r" > fo.in
../p8xemu -N -i fo.in -c fo.img -l 400000000 eeprom.bin > fo.out 2>/dev/null || true
ls_root | grep -q '^TESTDIR$' || { echo "root:"; ls_root; fail "new-folder did not create /TESTDIR"; }
echo "  new folder: /TESTDIR created"

# ---- duplicate: select Z.TXT (3 Downs), f d ZED.TXT ENTER ------------------
mkdisk
printf "B\rrun /bin/finder.bin\r${DOWN}${DOWN}${DOWN}fdZED.TXT\r" > fo.in
../p8xemu -N -i fo.in -c fo.img -l 400000000 eeprom.bin > fo.out 2>/dev/null || true
ls_root | grep -q '^ZED.TXT$' || { echo "root:"; ls_root; fail "duplicate did not create /ZED.TXT"; }
ls_root | grep -q '^Z.TXT$'   || fail "duplicate removed the original /Z.TXT"
python3 $ROOT/tools/p8xfs.py get fo.img /ZED.TXT --out zed.out >/dev/null 2>&1
grep -q 'hello finder' zed.out || fail "the duplicate is not a byte copy of the original"
echo "  duplicate: /ZED.TXT is a copy, original intact"

# ---- rename: select Z.TXT, f r RENAMED.TXT ENTER --------------------------
mkdisk
printf "B\rrun /bin/finder.bin\r${DOWN}${DOWN}${DOWN}frRENAMED.TXT\r" > fo.in
../p8xemu -N -i fo.in -c fo.img -l 400000000 eeprom.bin > fo.out 2>/dev/null || true
ls_root | grep -q '^RENAMED.TXT$' || { echo "root:"; ls_root; fail "rename did not create /RENAMED.TXT"; }
ls_root | grep -q '^Z.TXT$' && fail "rename left the old name /Z.TXT behind"
echo "  rename: /Z.TXT -> /RENAMED.TXT"

# ---- delete: select Z.TXT, f x y (confirm) --------------------------------
mkdisk
printf "B\rrun /bin/finder.bin\r${DOWN}${DOWN}${DOWN}fxy" > fo.in
../p8xemu -N -i fo.in -c fo.img -l 400000000 eeprom.bin > fo.out 2>/dev/null || true
ls_root | grep -q '^Z.TXT$' && { echo "root:"; ls_root; fail "delete did not remove /Z.TXT"; }
echo "  delete: /Z.TXT removed (after Y confirm)"

# ---- move: select Z.TXT, f m /bin ENTER -> /bin/Z.TXT --------------------
mkdisk
printf "B\rrun /bin/finder.bin\r${DOWN}${DOWN}${DOWN}fm/bin\r" > fo.in
../p8xemu -N -i fo.in -c fo.img -l 400000000 eeprom.bin > fo.out 2>/dev/null || true
python3 $ROOT/tools/p8xfs.py ls fo.img /bin 2>/dev/null | awk '{print $1}' | grep -q '^Z.TXT$' \
    || fail "move did not place /bin/Z.TXT"
ls_root | grep -q '^Z.TXT$' && fail "move left /Z.TXT at the root"
echo "  move: /Z.TXT -> /bin/Z.TXT"

# ---- delete CANCEL: f x n keeps the file ----------------------------------
mkdisk
printf "B\rrun /bin/finder.bin\r${DOWN}${DOWN}${DOWN}fxn" > fo.in
../p8xemu -N -i fo.in -c fo.img -l 400000000 eeprom.bin > fo.out 2>/dev/null || true
ls_root | grep -q '^Z.TXT$' || fail "delete-cancel (N) still removed /Z.TXT"
echo "  delete cancel: N kept /Z.TXT"

echo "C-FINDER-FILEOPS TEST: PASS (FILE menu: new folder, duplicate, rename, delete + cancel)"
