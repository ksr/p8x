#!/usr/bin/env python3
"""p8xwindow.py -- a live P8X display + mouse in your BROWSER, for p8xemu -W.

Apple's system Tk (8.5 Aqua) won't repaint reliably, so the viewer is a browser
page instead. This is a bridge: it listens on the Unix socket the emulator's -W
mode connects to (framebuffer in, mouse out), and serves a localhost page that
draws each frame on a <canvas> (raw RGB via putImageData -- no image encoding)
over a WebSocket, sending mouse events back. Keyboard/console stay on the
terminal running the emulator; this page is display + pointer only.

  tools/p8xwindow.py --sock /tmp/p8x.sock [--scale 2] [--port N]

Run this FIRST (it opens the browser and listens); then start p8xemu -W <sock>.
os/run-window.sh wires both together. Pure stdlib -- nothing to install.

Emulator <-> bridge (Unix socket):
  emulator -> bridge : 'F' w16 h16 then w*h*3 RGB (a full frame, on change)
  bridge -> emulator : 'M' x16 y16 btn8   (btn bit0 left, bit1 right)
Bridge <-> browser (WebSocket, binary):
  bridge -> browser  : w16 h16 then w*h*3 RGB
  browser -> bridge  : btn8 x16 y16
"""
import argparse, base64, hashlib, os, select, socket, struct, sys, threading, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def recvn(sock, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return bytes(buf)


def emu_frame(sock):
    """Read one 'F' w16 h16 + payload frame from the emulator socket."""
    hdr = recvn(sock, 5)
    if not hdr or hdr[0:1] != b"F":
        return None
    w, h = struct.unpack(">HH", hdr[1:5])
    rgb = recvn(sock, w * h * 3)
    if rgb is None:
        return None
    return struct.pack(">HH", w, h) + rgb          # w,h,rgb -- exactly the WS payload


def ws_send(sock, data):
    """Send one unmasked binary WebSocket frame."""
    n = len(data)
    hdr = bytearray([0x82])                         # FIN + binary
    if n < 126:
        hdr.append(n)
    elif n < 65536:
        hdr.append(126); hdr += struct.pack(">H", n)
    else:
        hdr.append(127); hdr += struct.pack(">Q", n)
    sock.sendall(bytes(hdr) + data)


def ws_recv(sock):
    """Receive one WebSocket frame's payload (handles masking); None on close."""
    b = recvn(sock, 2)
    if not b:
        return None
    op = b[0] & 0x0F
    masked = b[1] & 0x80
    n = b[1] & 0x7F
    if n == 126:
        n = struct.unpack(">H", recvn(sock, 2))[0]
    elif n == 127:
        n = struct.unpack(">Q", recvn(sock, 8))[0]
    mask = recvn(sock, 4) if masked else b"\0\0\0\0"
    data = recvn(sock, n)
    if data is None:
        return None
    if op == 0x8:                                   # close
        return None
    data = bytearray(data)
    for i in range(len(data)):
        data[i] ^= mask[i % 4]
    return bytes(data)


PAGE = """<!doctype html><html><head><meta charset=utf-8><title>P8X mouse pad</title>
<style>html,body{margin:0;background:#0e131a;color:#8fa6bd;height:100%%;
font-family:system-ui,-apple-system,sans-serif;display:flex;flex-direction:column;
align-items:center;justify-content:center;gap:10px;user-select:none}
#hdr{font-size:13px;color:#6f8296}#s{font:12px ui-monospace,monospace;color:#5f9}
canvas{image-rendering:pixelated;background:#000;box-shadow:0 0 0 1px #2a3644;cursor:none}</style>
</head><body>
<div id=hdr>P8X <b>mouse pad</b> — move &amp; click here; the pointer is on the LCD</div>
<canvas id=c width=480 height=272 style="width:%dpx;height:%dpx"></canvas>
<div id=s>connecting…</div>
<script>
const W=480,H=272,cv=document.getElementById('c'),ctx=cv.getContext('2d'),st=document.getElementById('s');
const im=ctx.createImageData(W,H); let frame=null, mx=W>>1, my=H>>1, buttons=0, ws, connected=false;
function redraw(){
  if(frame){ im.data.set(frame); ctx.putImageData(im,0,0); }
  else { ctx.fillStyle='#000'; ctx.fillRect(0,0,W,H); }
  ctx.lineWidth=1; ctx.strokeStyle = buttons?'#ff5555':'#44ff88';
  ctx.beginPath(); ctx.moveTo(mx+0.5,0); ctx.lineTo(mx+0.5,H);
  ctx.moveTo(0,my+0.5); ctx.lineTo(W,my+0.5); ctx.stroke();
  ctx.strokeRect(mx-3.5,my-3.5,7,7);
  st.textContent = 'x='+mx+' y='+my+(buttons?('  ['+(buttons&1?'L':'')+(buttons&2?'R':'')+']'):'')
    + (connected?'':'  — waiting for emulator');
}
function connect(){
  ws=new WebSocket('ws://'+location.host+'/ws'); ws.binaryType='arraybuffer';
  ws.onopen=()=>{connected=true;redraw();};
  ws.onmessage=e=>{const a=new Uint8Array(e.data); const d=im.data;   // [w16,h16,rgb] mirror (cardless)
    let p=4; for(let i=0,j=0;i<W*H;i++){d[j++]=a[p++];d[j++]=a[p++];d[j++]=a[p++];d[j++]=255;}
    frame=new Uint8ClampedArray(d); redraw();};
  ws.onclose=()=>{connected=false;redraw();setTimeout(connect,500);};
}
connect(); redraw();
function px(e){const r=cv.getBoundingClientRect();
  mx=Math.max(0,Math.min(W-1,Math.floor((e.clientX-r.left)*W/r.width)));
  my=Math.max(0,Math.min(H-1,Math.floor((e.clientY-r.top)*H/r.height)));}
function send(){if(ws&&ws.readyState==1){const b=new Uint8Array(5);b[0]=buttons;
  b[1]=mx>>8;b[2]=mx&255;b[3]=my>>8;b[4]=my&255;ws.send(b);}}
cv.addEventListener('mousemove',e=>{px(e);send();redraw();});
cv.addEventListener('mousedown',e=>{buttons|=(e.button===2?2:1);px(e);send();redraw();e.preventDefault();});
cv.addEventListener('mouseup',e=>{buttons&=~(e.button===2?2:1);px(e);send();redraw();e.preventDefault();});
cv.addEventListener('contextmenu',e=>e.preventDefault());
</script></body></html>"""


class Bridge(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, addr, sockpath, scale):
        super().__init__(addr, Handler)
        self.scale = scale
        self.emu = None
        self.emu_ready = threading.Event()
        try:
            os.unlink(sockpath)
        except OSError:
            pass
        self.usrv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.usrv.bind(sockpath)
        self.usrv.listen(1)
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self):
        while True:
            conn, _ = self.usrv.accept()
            self.emu = conn
            self.emu_ready.set()
            print("p8xwindow: emulator connected", file=sys.stderr)
            # wait until this connection drops, then accept a fresh one
            while True:
                try:
                    if conn.recv(1, socket.MSG_PEEK) == b"":
                        break
                except OSError:
                    break
                except Exception:
                    break
            self.emu_ready.clear()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == "/":
            body = (PAGE % (int(480 * self.server.scale), int(272 * self.server.scale))).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/ws":
            self.serve_ws()
        else:
            self.send_error(404)

    def serve_ws(self):
        key = self.headers.get("Sec-WebSocket-Key")
        if not key:
            self.send_error(400); return
        acc = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
        self.wfile.write(("HTTP/1.1 101 Switching Protocols\r\n"
                          "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                          "Sec-WebSocket-Accept: " + acc + "\r\n\r\n").encode())
        self.wfile.flush()
        ws = self.connection
        self.server.emu_ready.wait()
        emu = self.server.emu
        try:
            while True:
                r, _, _ = select.select([ws, emu], [], [], 1.0)
                if emu in r:
                    frame = emu_frame(emu)
                    if frame is None:
                        break
                    ws_send(ws, frame)
                if ws in r:
                    msg = ws_recv(ws)
                    if msg is None:
                        break
                    if len(msg) >= 5:
                        btn = msg[0]; x = (msg[1] << 8) | msg[2]; y = (msg[3] << 8) | msg[4]
                        try:
                            emu.sendall(b"M" + struct.pack(">HHB", x, y, btn))
                        except OSError:
                            pass
        except (OSError, ValueError):
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sock", required=True)
    ap.add_argument("--scale", type=float, default=2.0)   # window size = 480*scale x 272*scale
    ap.add_argument("--port", type=int, default=0, help="0 = pick a free port")
    a = ap.parse_args()
    srv = Bridge(("127.0.0.1", a.port), a.sock, a.scale)
    url = "http://127.0.0.1:%d/" % srv.server_port
    if os.environ.get("P8X_NO_OPEN"):
        print("p8xwindow: mouse pad at %s" % url, file=sys.stderr)
    else:
        print("p8xwindow: mouse pad at %s  (opening browser)" % url, file=sys.stderr)
        try:
            webbrowser.open(url)
        except Exception:
            pass
    srv.serve_forever()


if __name__ == "__main__":
    main()
