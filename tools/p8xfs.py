#!/usr/bin/env python3
"""p8xfs - host-side tool for P8XFS v1 disk images (the flat filesystem the
P8X ROM monitor formats and P8X/OS reads).

A P8XFS v1 volume is a flat sequence of 512-byte sectors (LBAs):

    LBA 0        boot block: 'P8', version, OSCNT, free-pointer
    LBA 1..32    OS image (loaded to $8000 by the monitor's B command)
    LBA 33..64   directory: 512 x 32-byte entries
    LBA 65..     file data, contiguous extents (allocated at the free pointer)

This matches firmware/p8xmon.asm (F/B commands) and the on-disk format in
hardware/cf-card/p8x-cf-os-design.md. The hierarchical v2 layout in
p8xfs-v2-hierarchical.md is a later upgrade; this tool is v1.

Usage:
    p8xfs.py create  img [--sectors N]          format a fresh volume
    p8xfs.py boot    img osimage.bin            install OS image at LBA 1
    p8xfs.py put     img file [--name N] [--load A] [--exec A]
    p8xfs.py get     img name [--out path]
    p8xfs.py ls      img
"""
import sys, os, struct, argparse, math

SEC      = 512
BOOT_LBA = 0
OS_LBA   = 1
OS_MAX   = 32            # OS image spans LBA 1..32 (16 KB)
DIR_LBA  = 33
DIR_SECS = 32           # LBA 33..64 -> 512 entries
DATA_LBA = 65
ENT      = 32           # directory entry size
ENT_PER_SEC = SEC // ENT

# entry flags
F_END = 0x00            # end-of-directory marker
F_FILE = 0x01
F_DIR = 0x02
F_DEL = 0xFF


def read_img(path):
    with open(path, "rb") as f:
        return bytearray(f.read())


def write_img(path, img):
    with open(path, "wb") as f:
        f.write(img)


def sec(img, lba):
    """Return a memoryview of one sector, growing the image if needed."""
    end = (lba + 1) * SEC
    if len(img) < end:
        img.extend(b"\x00" * (end - len(img)))
    return memoryview(img)[lba * SEC: end]


def get_free(img):
    return struct.unpack_from("<H", img, BOOT_LBA * SEC + 4)[0]


def set_free(img, lba):
    struct.pack_into("<H", img, BOOT_LBA * SEC + 4, lba)


def get_oscnt(img):
    return img[BOOT_LBA * SEC + 3]


# ---- directory entry helpers ------------------------------------------------
def ent_off(i):
    return DIR_LBA * SEC + i * ENT


def unpack_entry(img, i):
    o = ent_off(i)
    name = bytes(img[o:o + 12])
    start, length = struct.unpack_from("<II", img, o + 12)
    load, exec_ = struct.unpack_from("<HH", img, o + 20)
    flags = img[o + 24]
    return dict(name=name, start=start, length=length, load=load,
                exec=exec_, flags=flags)


def pack_entry(img, i, name, start, length, load, exec_, flags):
    o = ent_off(i)
    nm = name.upper().encode("ascii", "replace")[:12].ljust(12, b" ")
    img[o:o + 12] = nm
    struct.pack_into("<IIHHB", img, o + 12, start, length, load, exec_, flags)
    # spare 25..31 left as-is (zeroed on format)


def find_free_slot(img):
    """First $FF (deleted) or $00 (end) slot. Returns (index, is_end)."""
    for i in range(DIR_SECS * ENT_PER_SEC):
        f = img[ent_off(i) + 24]
        if f == F_DEL:
            return i, False
        if f == F_END:
            return i, True
    raise SystemExit("p8xfs: directory full")


# ---- commands ---------------------------------------------------------------
def cmd_create(a):
    nsec = max(a.sectors, DATA_LBA)
    img = bytearray(b"\x00" * (nsec * SEC))
    b = sec(img, BOOT_LBA)
    b[0:2] = b"P8"
    b[2] = 1                       # version 1
    b[3] = 0                       # OSCNT = 0 (no OS yet)
    struct.pack_into("<H", img, 4, DATA_LBA)   # free pointer
    # directory region already zeroed -> first entry flag $00 = end
    write_img(a.img, img)
    print("created %s: %d sectors, free@LBA %d" % (a.img, nsec, DATA_LBA))


def cmd_boot(a):
    img = read_img(a.img)
    data = read_img(a.osimage)
    nsec = math.ceil(len(data) / SEC)
    if nsec > OS_MAX:
        raise SystemExit("p8xfs: OS image %d sectors > %d max" % (nsec, OS_MAX))
    for s in range(nsec):
        chunk = data[s * SEC:(s + 1) * SEC].ljust(SEC, b"\x00")
        sec(img, OS_LBA + s)[:] = chunk
    img[BOOT_LBA * SEC + 3] = nsec     # OSCNT
    write_img(a.img, img)
    print("installed %s as OS: %d sector(s), OSCNT=%d" %
          (a.osimage, nsec, nsec))


def cmd_put(a):
    img = read_img(a.img)
    data = read_img(a.file)
    name = a.name or os.path.basename(a.file)
    nsec = max(1, math.ceil(len(data) / SEC))
    start = get_free(img)
    for s in range(nsec):
        chunk = data[s * SEC:(s + 1) * SEC].ljust(SEC, b"\x00")
        sec(img, start + s)[:] = chunk
    i, _ = find_free_slot(img)
    pack_entry(img, i, name, start, len(data), a.load, a.exec, F_FILE)
    set_free(img, start + nsec)
    write_img(a.img, img)
    print("put %-12s %5d bytes  LBA %d..%d  load=%04X exec=%04X" %
          (name, len(data), start, start + nsec - 1, a.load, a.exec))


def cmd_get(a):
    img = read_img(a.img)
    want = a.name.upper().encode().ljust(12, b" ")
    for i in range(DIR_SECS * ENT_PER_SEC):
        e = unpack_entry(img, i)
        if e["flags"] == F_END:
            break
        if e["flags"] == F_FILE and e["name"] == want:
            data = bytes(img[e["start"] * SEC: e["start"] * SEC + e["length"]])
            out = a.out or a.name
            write_img(out, bytearray(data))
            print("get %s -> %s (%d bytes)" % (a.name, out, e["length"]))
            return
    raise SystemExit("p8xfs: %s not found" % a.name)


def cmd_ls(a):
    img = read_img(a.img)
    print("Volume %s  version %d  OSCNT %d  free@LBA %d" %
          (a.img, img[2], get_oscnt(img), get_free(img)))
    print("%-12s %7s  %-9s %s" % ("NAME", "BYTES", "LBA", "LOAD/EXEC"))
    n = 0
    for i in range(DIR_SECS * ENT_PER_SEC):
        e = unpack_entry(img, i)
        if e["flags"] == F_END:
            break
        if e["flags"] == F_DEL:
            continue
        kind = "<DIR>" if e["flags"] == F_DIR else ""
        print("%-12s %7d  %-9d %04X/%04X %s" % (
            e["name"].decode("latin1").rstrip(), e["length"], e["start"],
            e["load"], e["exec"], kind))
        n += 1
    print("%d file(s)" % n)


def main():
    p = argparse.ArgumentParser(prog="p8xfs", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("create"); c.add_argument("img")
    c.add_argument("--sectors", type=int, default=256); c.set_defaults(fn=cmd_create)

    c = sub.add_parser("boot"); c.add_argument("img"); c.add_argument("osimage")
    c.set_defaults(fn=cmd_boot)

    c = sub.add_parser("put"); c.add_argument("img"); c.add_argument("file")
    c.add_argument("--name"); c.add_argument("--load", type=lambda x: int(x, 0), default=0xA000)
    c.add_argument("--exec", type=lambda x: int(x, 0), default=0xA000)
    c.set_defaults(fn=cmd_put)

    c = sub.add_parser("get"); c.add_argument("img"); c.add_argument("name")
    c.add_argument("--out"); c.set_defaults(fn=cmd_get)

    c = sub.add_parser("ls"); c.add_argument("img"); c.set_defaults(fn=cmd_ls)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
