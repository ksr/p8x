#!/bin/sh
# FDELETE on a subdirectory whose extent sits past LBA 255. FDEL_CORE used to
# read/write the directory sector with only the low byte of the dir LBA (LBA1=0),
# so a `del` in a high-LBA subdir tombstoned the WRONG sector and silently did
# nothing — leaving duplicate/stale entries (the `make` in /src/os-bios "builds
# everything" bug: MK.RUN was never replaced). Guard the 16-bit fix: pad the disk
# so a subdir lands beyond LBA 255, create a file in it, `del` it on-target, and
# confirm it is actually gone.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "FDELETE-HILBA TEST: FAIL — $1"; [ -n "$2" ] && echo "$2"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o oshl.bin --base 0x2000 >/dev/null

rm -f hl.img pad.bin
python3 $ROOT/tools/p8xfs.py create hl.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   hl.img oshl.bin >/dev/null
# ~140 KB padding file pushes the next allocation past LBA 255 (256*512 = 128 KB).
python3 -c "open('pad.bin','wb').write(b'P'*143360)"
python3 $ROOT/tools/p8xfs.py put   hl.img pad.bin --name /PAD.BIN >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir hl.img /sub >/dev/null
printf 'hello\n' > f.txt
python3 $ROOT/tools/p8xfs.py put   hl.img f.txt --name /sub/F.TXT >/dev/null

# sanity: the subdir's extent really is beyond LBA 255 (else the test proves nothing)
lba=$(python3 - <<'PY'
import sys; sys.path.insert(0,"$ROOT/tools".replace("$ROOT","../.."))
import p8xfs as fs
img=fs.read_img("hl.img")
for e in fs.iter_dir(img, fs.ROOT_LBA, fs.ROOT_SECS):
    if e["name"]==b"sub         ": print(e["start"])
PY
)
[ "${lba:-0}" -gt 255 ] || fail "test setup: /sub at LBA ${lba:-?}, not > 255"

out=$(printf 'B\rdel /sub/F.TXT\rdir /sub\r' | \
      ../p8xemu -l 400000000 -c hl.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
# after delete, the on-target listing of /sub must NOT show F.TXT
echo "$out" | sed -n '/dir \/sub/,$p' | grep -qi 'F.TXT' && \
    fail "F.TXT still listed after del -> FDELETE did not remove it in a >255-LBA dir" "$out"
# and host-side: exactly zero live F.TXT entries remain
n=$(python3 - <<'PY'
import sys; sys.path.insert(0,"../../tools")
import p8xfs as fs
img=fs.read_img("hl.img")
dlba,dsecs=fs.resolve_dir(img,"/sub")
print(sum(1 for e in fs.iter_dir(img,dlba,dsecs) if e["flags"]==fs.F_FILE and e["name"]==b"F.TXT       "))
PY
)
[ "$n" = "0" ] || fail "host-side: $n live F.TXT entries remain after del"
echo "FDELETE-HILBA TEST: PASS"
