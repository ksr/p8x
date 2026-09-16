#!/usr/bin/env python3
"""p8xwindow.py -- a live P8X display window + mouse, for the emulator's -W mode.

The emulator (p8xemu -W <socket>) renders the 480x272 panel locally and streams
it here; this window shows it and sends mouse events back, which the emulator
turns into the xterm SGR reports lib_ptr already reads. Keyboard and console stay
on the terminal that runs the emulator -- this window is display + pointer only.

  tools/p8xwindow.py --sock /tmp/p8x.sock [--scale 2]

Run this FIRST (it listens); then start the emulator with -W <same socket>.
os/run-window.sh wires both together. Pure Tkinter (bundled) -- nothing to install.

Protocol:
  emulator -> window : 'F' w16 h16 then w*h*3 RGB bytes (a full frame, on change)
  window -> emulator : 'M' x16 y16 btn8   (btn bit0 left, bit1 right)
"""
import argparse, os, socket, struct, sys, threading, tempfile, tkinter


def read_exact(sock, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return bytes(buf)


class Window:
    def __init__(self, sockpath, scale):
        self.scale = scale
        self.conn = None
        self.latest = None          # (w, h, rgb) most recent frame
        self.shown = None           # id() of the frame currently displayed
        self.buttons = 0            # current button mask
        self.lock = threading.Lock()
        self.ppm_path = os.path.join(tempfile.gettempdir(), "p8xwin-%d.ppm" % os.getpid())

        # listening socket -- the window is the server, the emulator connects
        try:
            os.unlink(sockpath)
        except OSError:
            pass
        self.srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.srv.bind(sockpath)
        self.srv.listen(1)

        self.root = tkinter.Tk()
        self.root.title("P8X")
        self.root.resizable(False, False)
        self.label = tkinter.Label(self.root, bd=0, bg="#000000",
                                   width=480 * scale, height=272 * scale)
        self.label.pack()
        self.img = None
        for seq in ("<Motion>", "<ButtonPress>", "<ButtonRelease>"):
            self.label.bind(seq, self.on_mouse)
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

        threading.Thread(target=self.reader, daemon=True).start()
        self.root.after(16, self.tick)

    # ---- socket reader thread: accept, then pull full frames ----------------
    def reader(self):
        try:
            self.conn, _ = self.srv.accept()
        except OSError:
            return
        while True:
            hdr = read_exact(self.conn, 5)
            if not hdr or hdr[0:1] != b'F':
                break
            w, h = struct.unpack(">HH", hdr[1:5])
            rgb = read_exact(self.conn, w * h * 3)
            if rgb is None:
                break
            with self.lock:
                self.latest = (w, h, rgb)

    # ---- Tk timer: refresh the image when a new frame arrived ---------------
    def tick(self):
        with self.lock:
            frame = self.latest
        if frame is not None and id(frame) != self.shown:
            self.shown = id(frame)
            w, h, rgb = frame
            with open(self.ppm_path, "wb") as f:
                f.write(b"P6\n%d %d\n255\n" % (w, h))
                f.write(rgb)
            img = tkinter.PhotoImage(file=self.ppm_path)
            if self.scale != 1:
                img = img.zoom(self.scale)
            self.img = img                      # keep a reference (Tk GCs otherwise)
            self.label.config(image=img)
        self.root.after(16, self.tick)

    # ---- mouse -> emulator --------------------------------------------------
    def on_mouse(self, e):
        s = self.scale
        x = max(0, min(479, e.x // s))
        y = max(0, min(271, e.y // s))
        # Tk button state: e.state bit8 = left(1), bit10 = right(3); update on press/release
        if e.type == tkinter.EventType.ButtonPress:
            if e.num == 1: self.buttons |= 1
            elif e.num == 3: self.buttons |= 2
        elif e.type == tkinter.EventType.ButtonRelease:
            if e.num == 1: self.buttons &= ~1
            elif e.num == 3: self.buttons &= ~2
        conn = self.conn
        if conn is not None:
            try:
                conn.sendall(b'M' + struct.pack(">HHB", x, y, self.buttons))
            except OSError:
                pass

    def on_close(self):
        try:
            if self.conn: self.conn.close()
        except OSError:
            pass
        self.root.destroy()

    def run(self):
        self.root.mainloop()
        try:
            os.unlink(self.ppm_path)
        except OSError:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sock", required=True, help="Unix socket path (emulator connects here)")
    ap.add_argument("--scale", type=int, default=2, help="pixel scale factor (default 2)")
    a = ap.parse_args()
    print("p8xwindow: listening on %s (scale %dx) -- start p8xemu -W %s"
          % (a.sock, a.scale, a.sock), file=sys.stderr)
    Window(a.sock, a.scale).run()


if __name__ == "__main__":
    main()
