#!/usr/bin/env python3
"""p8img.py -- convert an image to P8I, the P8X display's own format.

    ./p8img.py photo.png [out.p8i] [--width N] [--no-dither] [--preview out.ppm]

P8I (STAGE6-DESIGN.md): a 10-byte self-describing header, then raw RGB565.

    offset  size  field
         0     3  magic "P8I"
         3     1  version, 0x01
         4     2  width,  little-endian
         6     2  height, little-endian
         8     1  depth, 0x10 = RGB565 -- ask, don't assume
         9     1  reserved (flags someday)
        10   ...  width*height RGB565 words, row-major, little-endian

The geometry lives HERE, not in the IMAGE statement, for the same reason the
device's IDENT record carries its geometry: the file describes itself, so
`IMAGE X,Y,name$` cannot be lied to. Little-endian words match the GCOL/GCOLH
write order, so the on-target loader is read-byte -> GCOL, read-byte -> GCOLH,
PLOT.

DITHERING HAPPENS HERE, on the host, where a real algorithm is cheap -- the
framebuffer never needs the source's extra bits (see the 24 bpp entry in the
stage-6 rejected alternatives). Floyd-Steinberg to the 565 grid, on by
default; --no-dither truncates, which is right for flat-colour art where
dither noise would only speckle clean edges.

Images wider than the 480x272 screen are scaled down to fit by default (the
device would only discard the off-screen remainder); --width forces a size.
Uses Pillow if present, else falls back to sips + BMP parsing (macOS,
dependency-free -- the house preference).
"""
import os, struct, subprocess, sys, tempfile

SCREEN_W, SCREEN_H = 480, 272


def load_rgb(path, force_w=None):
    """-> (w, h, bytes rgb888 row-major). Scales to fit the screen."""
    try:
        from PIL import Image
        im = Image.open(path).convert("RGB")
        w, h = im.size
        tw = force_w or w
        if force_w or w > SCREEN_W or h > SCREEN_H:
            scale = min((force_w or SCREEN_W) / w, SCREEN_H / h, 1.0) \
                    if not force_w else force_w / w
            tw, th = max(1, round(w * scale)), max(1, round(h * scale))
            im = im.resize((tw, th), Image.LANCZOS)
        return im.size[0], im.size[1], im.tobytes()
    except ImportError:
        pass
    # sips + uncompressed 24-bit BMP: no dependencies, macOS only
    with tempfile.NamedTemporaryFile(suffix=".bmp", delete=False) as t:
        tmp = t.name
    args = ["sips", "-s", "format", "bmp", path, "--out", tmp]
    if force_w:
        args[1:1] = ["--resampleWidth", str(force_w)]
    subprocess.run(args, check=True, capture_output=True)
    d = open(tmp, "rb").read(); os.unlink(tmp)
    if d[:2] != b"BM":
        sys.exit("p8img: sips did not produce a BMP")
    off  = struct.unpack("<I", d[10:14])[0]
    w    = struct.unpack("<i", d[18:22])[0]
    h    = struct.unpack("<i", d[22:26])[0]
    bpp  = struct.unpack("<H", d[28:30])[0]
    comp = struct.unpack("<I", d[30:34])[0]
    if bpp != 24 or comp != 0:
        sys.exit("p8img: expected uncompressed 24-bit BMP from sips (got %d bpp)" % bpp)
    stride = (w * 3 + 3) & ~3
    out = bytearray(w * abs(h) * 3)
    flip = h > 0                      # positive height = bottom-up rows
    h = abs(h)
    for y in range(h):
        src = off + (h - 1 - y if flip else y) * stride
        for x in range(w):
            b_, g_, r_ = d[src + x*3 : src + x*3 + 3]
            i = (y*w + x) * 3
            out[i:i+3] = bytes((r_, g_, b_))
    return w, h, bytes(out)


def to_565(w, h, rgb, dither=True):
    """Floyd-Steinberg to the 565 grid; returns a list of 16-bit words."""
    if not dither:
        px = []
        for i in range(0, len(rgb), 3):
            r, g, b = rgb[i], rgb[i+1], rgb[i+2]
            px.append(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3))
        return px
    buf = [float(v) for v in rgb]
    px = []
    for y in range(h):
        for x in range(w):
            i = (y*w + x) * 3
            out_word = 0
            for c, (bits, shift) in enumerate(((5, 11), (6, 5), (5, 0))):
                v = min(255.0, max(0.0, buf[i+c]))
                q = round(v * ((1 << bits) - 1) / 255.0)      # nearest 565 level
                shown = q * 255.0 / ((1 << bits) - 1)          # what the panel shows
                err = v - shown
                out_word |= q << shift
                # spread the error: 7/16 right, 3/16 down-left, 5/16 down, 1/16 down-right
                if x + 1 < w:              buf[i+3+c]         += err * 7/16
                if y + 1 < h:
                    if x > 0:              buf[i + (w-1)*3 + c] += err * 3/16
                    buf[i + w*3 + c]                            += err * 5/16
                    if x + 1 < w:          buf[i + (w+1)*3 + c] += err * 1/16
            px.append(out_word)
    return px


def write_p8i(path, w, h, px):
    with open(path, "wb") as f:
        f.write(b"P8I" + bytes((1,)) + struct.pack("<HH", w, h) + bytes((16, 0)))
        f.write(struct.pack("<%dH" % len(px), *px))


def write_preview(path, w, h, px):
    """565 -> 888 by bit replication, exactly as the emulator's PPM writer."""
    with open(path, "wb") as f:
        f.write(b"P6\n%d %d\n255\n" % (w, h))
        for p in px:
            r5, g6, b5 = (p >> 11) & 31, (p >> 5) & 63, p & 31
            f.write(bytes(((r5 << 3) | (r5 >> 2), (g6 << 2) | (g6 >> 4),
                           (b5 << 3) | (b5 >> 2))))


def main():
    args = sys.argv[1:]
    dither, force_w, preview = True, None, None
    if "--no-dither" in args: dither = False; args.remove("--no-dither")
    if "--width" in args:
        i = args.index("--width"); force_w = int(args[i+1]); del args[i:i+2]
    if "--preview" in args:
        i = args.index("--preview"); preview = args[i+1]; del args[i:i+2]
    if not args:
        sys.exit(__doc__.strip().split("\n")[2].strip())
    src = args[0]
    dst = args[1] if len(args) > 1 else os.path.splitext(src)[0] + ".p8i"

    w, h, rgb = load_rgb(src, force_w)
    px = to_565(w, h, rgb, dither)
    write_p8i(dst, w, h, px)
    print("%s: %dx%d, %d bytes (%s)" %
          (dst, w, h, 10 + 2*len(px), "dithered" if dither else "truncated"))
    if preview:
        write_preview(preview, w, h, px)
        print("%s: what the panel will show" % preview)


if __name__ == "__main__":
    main()
