#!/bin/sh
# vi — minimal VT100 screen editor (os/commands/vi.c). Driven headlessly: the
# emulator's console reads raw keys from stdin (CONIN), so we feed a keystroke
# script after the RUN line and check the resulting file (the ANSI redraw goes to
# stdout, which we discard). Exercises: append (A), insert (i), delete-char (x),
# delete-line (dd), open-line (o), save+quit (:wq), and new-file creation.
set -e
cd "$(dirname "$0")"
ROOT=../..
ESC=$(printf '\033')

cp $ROOT/microcode/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/vi.c -o vi.pp.c
python3 $ROOT/compiler/p8cc.py vi.pp.c -o vi.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py vi.asm -o vi.bin --base 0x7A00 >/dev/null

mkdisk() {   # fresh disk with /bin/vi.bin and a two-line T.TXT
    rm -f vi.img
    python3 $ROOT/tools/p8xfs.py create vi.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   vi.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  vi.img /bin >/dev/null
    python3 $ROOT/tools/p8xfs.py put vi.img vi.bin --name /bin/vi.bin --load 0x7A00 --exec 0x7A00 >/dev/null
    printf 'hello\r\nworld\r\n' > vt.dat
    python3 $ROOT/tools/p8xfs.py put vi.img vt.dat --name /T.TXT --load 0 --exec 0 >/dev/null
}
edit() {   # $1 = keystrokes after opening $2 ; runs vi headlessly
    printf "B\rrun /bin/vi.bin $2\r$1" | ../p8xemu -l 200000000 -c vi.img eeprom.bin >/dev/null 2>&1
}
getf() { python3 $ROOT/tools/p8xfs.py get vi.img "$1" --out vg.out >/dev/null 2>&1; }

# 1) append to line 1:  A " X" Esc :wq  -> "hello X\nworld\n" (vi saves LF)
mkdisk
edit "A X$ESC:wq\r" T.TXT
getf /T.TXT
python3 -c "import sys;d=open('vg.out','rb').read();sys.exit(0 if d==b'hello X\nworld\n' else 1)" \
    || { echo "OS-VI TEST: FAIL — append (A)"; python3 -c "print(repr(open('vg.out','rb').read()))"; exit 1; }

# 2) x (del 'h'), j, dd (del 'world'), o "new" Esc, :wq  -> "ello\nnew\n"
mkdisk
edit "xjddonew$ESC:wq\r" T.TXT
getf /T.TXT
python3 -c "import sys;d=open('vg.out','rb').read();sys.exit(0 if d==b'ello\nnew\n' else 1)" \
    || { echo "OS-VI TEST: FAIL — x/dd/o edits"; python3 -c "print(repr(open('vg.out','rb').read()))"; exit 1; }

# 3) new file:  VI NEW.TXT ; i "first line" Esc :wq
mkdisk
edit "ifirst line$ESC:wq\r" NEW.TXT
getf /NEW.TXT || { echo "OS-VI TEST: FAIL — new file not created"; exit 1; }
python3 -c "import sys;d=open('vg.out','rb').read();sys.exit(0 if d==b'first line\n' else 1)" \
    || { echo "OS-VI TEST: FAIL — new-file content"; python3 -c "print(repr(open('vg.out','rb').read()))"; exit 1; }

# 4) :q on an unmodified file quits without writing — T.TXT keeps its ORIGINAL
#    bytes (the CRLF input fixture untouched; contrast the :wq cases which rewrite
#    with LF). Proves :q doesn't normalize line endings.
mkdisk
edit ":q\r" T.TXT
getf /T.TXT
python3 -c "import sys;d=open('vg.out','rb').read();sys.exit(0 if d==b'hello\r\nworld\r\n' else 1)" \
    || { echo "OS-VI TEST: FAIL — :q left the file changed"; exit 1; }

# 5) undo of x: x deletes 'h', u restores it -> file unchanged
mkdisk
edit "xu:wq\r" T.TXT
getf /T.TXT
python3 -c "import sys;d=open('vg.out','rb').read();sys.exit(0 if d==b'hello\nworld\n' else 1)" \
    || { echo "OS-VI TEST: FAIL — undo of x"; python3 -c "print(repr(open('vg.out','rb').read()))"; exit 1; }

# 6) undo of dd: dd deletes line 1, u reinserts it -> file unchanged
mkdisk
edit "ddu:wq\r" T.TXT
getf /T.TXT
python3 -c "import sys;d=open('vg.out','rb').read();sys.exit(0 if d==b'hello\nworld\n' else 1)" \
    || { echo "OS-VI TEST: FAIL — undo of dd"; python3 -c "print(repr(open('vg.out','rb').read()))"; exit 1; }

# 7) search: /world<CR> jumps to line 2, A! appends there -> "hello\r\nworld!\r\n"
mkdisk
edit "/world\rA!$ESC:wq\r" T.TXT
getf /T.TXT
python3 -c "import sys;d=open('vg.out','rb').read();sys.exit(0 if d==b'hello\nworld!\n' else 1)" \
    || { echo "OS-VI TEST: FAIL — search then edit at match"; python3 -c "print(repr(open('vg.out','rb').read()))"; exit 1; }

echo "OS-VI TEST: PASS"
