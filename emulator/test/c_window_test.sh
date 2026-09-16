#!/bin/sh
# The -W display/mouse WINDOW path: p8xemu renders the panel locally and streams
# it over a Unix socket to a viewer (tools/p8xwindow.py), taking mouse events back
# as xterm SGR into the console -- so finder is mouse-driven while keyboard stays
# on the terminal. This test stands in for the GUI with a headless mock socket:
#   1. the emulator connects and streams valid 480x272 frames (display path);
#   2. a mouse click sent over the socket reaches finder (it redraws) -- proving
#      the SGR injection + ESC[18t=480x272 map + lib_ptr decode all work.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "C-WINDOW TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o wos.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/finder.c -o wfnd.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py wfnd.pp.c -o wfnd.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py wfnd.asm -o wfnd.bin --base 0x5900 >/dev/null

rm -f w.img
python3 $ROOT/tools/p8xfs.py create w.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   w.img wos.bin >/dev/null
# a few root entries so the icon grid has more than one cell to move between
python3 $ROOT/tools/p8xfs.py put    w.img wfnd.bin --name /A.BIN --load 0x5900 --exec 0x5900 >/dev/null
python3 $ROOT/tools/p8xfs.py put    w.img wfnd.bin --name /B.BIN --load 0x5900 --exec 0x5900 >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  w.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    w.img wfnd.bin --name /bin/finder.bin --load 0x5900 --exec 0x5900 >/dev/null
python3 $ROOT/tools/p8xfs.py put    w.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

printf 'B\rfinder\r' > w.in
python3 - <<'PY' || fail "window path check failed"
import socket, subprocess, struct, os, sys
sock = os.path.abspath("w.sock")
try: os.unlink(sock)
except OSError: pass
srv=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); srv.bind(sock); srv.listen(1)
# big cycle cap: batch mode runs faster than wall-clock, so it must not exit
# mid-test (during the ~10s of socket waits); the harness terminates it when done.
p=subprocess.Popen(["../p8xemu","-N","-i","w.in","-W",sock,"-c","w.img","-l","50000000000","eeprom.bin"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
def rx(c,n):
    b=b""
    while len(b)<n:
        ch=c.recv(n-len(b))
        if not ch: return None
        b+=ch
    return b
def frame(c):
    h=rx(c,5)
    if not h or h[0:1]!=b'F': return None
    w,ht=struct.unpack(">HH",h[1:5])
    if (w,ht)!=(480,272): raise SystemExit("bad frame geometry %dx%d"%(w,ht))
    return rx(c,w*ht*3)
rc=1
try:
    srv.settimeout(15); conn,_=srv.accept()
    # 1) DISPLAY: drain frames until finder settles (a read times out)
    last=None; n=0; conn.settimeout(4.0)
    while True:
        try:
            f=frame(conn)
            if f is None: break
            if len(f)!=480*272*3: raise SystemExit("short frame")
            last=f; n+=1
        except socket.timeout:
            break
    if n<1: raise SystemExit("no frames streamed (display path)")
    # 2) CURSOR: a free move (no button) must draw the following cursor (1003)
    conn.sendall(b'M'+struct.pack(">HHB",200,150,0))
    curdrawn=False; conn.settimeout(4.0)
    try:
        for _ in range(3):
            f=frame(conn)
            if f is None: break
            if f!=last: curdrawn=True; last=f; break
    except socket.timeout: pass
    if not curdrawn: raise SystemExit("free move drew no cursor (1003 motion path)")
    # 3) MOUSE: click column 1 -> finder moves the selection -> it redraws
    conn.sendall(b'M'+struct.pack(">HHB",144,30,0))   # move there
    conn.sendall(b'M'+struct.pack(">HHB",144,30,1))   # left press
    conn.sendall(b'M'+struct.pack(">HHB",144,30,0))   # release
    changed=False; conn.settimeout(4.0)
    try:
        for _ in range(4):
            f=frame(conn)
            if f is None: break
            if f!=last: changed=True; break
    except socket.timeout:
        pass
    if not changed: raise SystemExit("click produced no redraw (mouse path)")
    print("  display: %d frames; free-move cursor drawn; click reached finder" % n)
    rc=0
finally:
    p.terminate()
sys.exit(rc)
PY

echo "C-WINDOW TEST: PASS (-W streams 480x272 frames; a socket mouse click drives finder)"
