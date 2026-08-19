#!/usr/bin/env python3
"""fput.py -- copy host files into the standard P8X disk image.

    ./fput.py notes.txt game.bas                 -> / of os/run-disk.img
    ./fput.py pics/*.p8i --to /PIC               -> into /PIC (--mkdir creates it)
    ./fput.py cmd.bin --as /BIN/CMD --load 0x6A00 --exec 0x6A00
    ./fput.py photo.p8i --board                  -> update image, then clone to
                                                    the FPGA's card via imgsend

The ONE image serves every target: the software emulator mounts it directly
(os/run.sh), so a put is visible on the next emulator boot with no further
step; the real FPGA runs a byte-for-byte clone of it, refreshed by --board
(or fpga/tang-nano-20k/tools/imgsend.py by hand -- the board must be sitting
at the monitor's '*' prompt, and the full clone takes ~3 minutes).

Unlike raw `p8xfs.py put`, an existing file of the same name is REPLACED
(tombstoned first) -- a transfer tool you cannot run twice is no tool at all.
Everything else is p8xfs law: leaf names are 12 characters and case-sensitive
(longer warns, --strict fails), a P8XFS path is /DIR/LEAF, and destination
directories must exist (or pass --mkdir). Images (PNG/JPEG/...) are NOT
converted -- run p8img.py first; this tool copies bytes verbatim.

--load/--exec matter only for binaries run by the OS (`run /BIN/X` loads at
--load, jumps to --exec; commands live at $6A00, the TPA). Data files ignore
them.
"""

import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import p8xfs as fs                                     # noqa: E402

REPO = os.path.dirname(HERE)
DEFAULT_IMG = os.path.join(REPO, "os", "run-disk.img")
IMGSEND = os.path.join(REPO, "fpga", "tang-nano-20k", "tools", "imgsend.py")


def main():
    p = argparse.ArgumentParser(
        prog="fput", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("files", nargs="+", help="host file(s) to copy in")
    p.add_argument("--img", default=DEFAULT_IMG,
                   help="disk image (default: the standard os/run-disk.img)")
    p.add_argument("--to", default="/", metavar="/DIR",
                   help="destination directory in the image (default /)")
    p.add_argument("--as", dest="dest_as", metavar="/DIR/NAME",
                   help="full destination path -- single file only")
    p.add_argument("--mkdir", action="store_true",
                   help="create the --to directory if it does not exist")
    p.add_argument("--load", type=lambda x: int(x, 0), default=0xB000)
    p.add_argument("--exec", type=lambda x: int(x, 0), default=0xB000)
    p.add_argument("--strict", action="store_true",
                   help="fail (don't just warn) on names over the 12-char field")
    p.add_argument("--board", action="store_true",
                   help="after updating the image, clone it to the FPGA's card "
                        "with imgsend (board must be at the monitor '*' prompt)")
    a = p.parse_args()

    if a.dest_as and len(a.files) > 1:
        raise SystemExit("fput: --as names ONE destination; got %d files"
                         % len(a.files))
    if not os.path.exists(a.img):
        raise SystemExit("fput: no disk image at %s\n"
                         "  (os/run.sh creates the standard one, or point "
                         "--img at another)" % a.img)
    for f in a.files:
        if not os.path.isfile(f):
            raise SystemExit("fput: no such file: %s" % f)

    fs.STRICT = a.strict
    img = fs.read_img(a.img)
    fs.require_v2(img)

    todir = "/" + a.to.strip("/")
    if a.dest_as is None and todir != "/":
        try:
            fs.resolve_dir(img, todir)
        except SystemExit:
            if not a.mkdir:
                raise SystemExit("fput: no directory %s in %s (--mkdir creates it)"
                                 % (todir, a.img))
            parent, leaf = fs.split_path(todir)
            pdir = fs.resolve_dir(img, parent)
            newlba = fs.alloc(img, fs.SUBDIR_SECS)
            fs.init_dir_extent(img, newlba, fs.SUBDIR_SECS, pdir[0], pdir[1])
            fs.add_entry(img, pdir[0], pdir[1], leaf, newlba,
                         fs.SUBDIR_SECS * fs.SEC, 0, 0, fs.F_DIR)
            print("mkdir %s" % todir)

    for f in a.files:
        dest = a.dest_as or (todir.rstrip("/") + "/" + os.path.basename(f))
        n, start, nsec = fs.put_file(img, f, dest, a.load, a.exec, replace=True)
        print("put %s -> %s  %d bytes  LBA %d..%d"
              % (f, dest, n, start, start + nsec - 1))

    fs.write_img(a.img, img)
    print("%s updated -- the emulator (os/run.sh) sees this on its next boot"
          % a.img)

    if a.board:
        print("\ncloning to the FPGA card -- needs the monitor '*' prompt "
              "(reload the bitstream if unsure); ~3 minutes...")
        r = subprocess.run([sys.executable, IMGSEND, a.img])
        if r.returncode != 0:
            raise SystemExit("fput: imgsend FAILED -- the card was NOT "
                             "(fully) updated; get the board to the monitor "
                             "prompt and retry")


if __name__ == "__main__":
    main()
