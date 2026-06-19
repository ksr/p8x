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
    p8xfs.py ls      img [path]
    p8xfs.py fsck    img                        verify; report reclaimable space

v2 (hierarchical) volumes — create with --v2; put/get/ls/mkdir take paths:
    p8xfs.py create  img --v2
    p8xfs.py mkdir   img /BIN
    p8xfs.py put     img file.bin --name /BIN/FILE.BIN
    p8xfs.py ls      img /BIN
    p8xfs.py tree    img
"""
import sys, os, struct, argparse, math

SEC      = 512
BOOT_LBA = 0
OS_LBA   = 1
OS_MAX   = 32            # OS image spans LBA 1..32 (16 KB)
ENT      = 32           # directory entry size
ENT_PER_SEC = SEC // ENT

# v1 (flat) layout
DIR_LBA  = 33
DIR_SECS = 32           # LBA 33..64 -> 512 entries
DATA_LBA = 65

# v2 (hierarchical) layout: root is a 4-sector directory extent at LBA 33; a
# directory is just a file whose extent holds 32-byte entries (entry 0 = '.',
# entry 1 = '..'). New extents allocate from LBA 37 up.
ROOT_LBA    = 33
ROOT_SECS   = 4         # 64 entries
SUBDIR_SECS = 4         # default size of a created subdirectory
DATA_V2     = 37

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
# An entry lives at a byte offset; directory extents are contiguous sectors, so
# entry i of a directory starting at dlba is at dlba*SEC + i*ENT.
def ent_abs(dlba, i):
    return dlba * SEC + i * ENT


def unpack_at(img, off):
    name = bytes(img[off:off + 12])
    start, length = struct.unpack_from("<II", img, off + 12)
    load, exec_ = struct.unpack_from("<HH", img, off + 20)
    return dict(name=name, start=start, length=length, load=load,
                exec=exec_, flags=img[off + 24], off=off)


def pack_at(img, off, name, start, length, load, exec_, flags):
    nm = (name.upper().encode("ascii", "replace") if isinstance(name, str)
          else name)[:12].ljust(12, b" ")
    img[off:off + 12] = nm
    struct.pack_into("<IIHHB", img, off + 12, start, length, load, exec_, flags)
    # spare 25..31 left as-is (zeroed on format)


# v1 wrappers (flat directory at DIR_LBA)
def ent_off(i):
    return ent_abs(DIR_LBA, i)


def unpack_entry(img, i):
    return unpack_at(img, ent_off(i))


def pack_entry(img, i, name, start, length, load, exec_, flags):
    pack_at(img, ent_off(i), name, start, length, load, exec_, flags)


def find_free_slot(img):
    """First $FF (deleted) or $00 (end) slot. Returns (index, is_end)."""
    for i in range(DIR_SECS * ENT_PER_SEC):
        f = img[ent_off(i) + 24]
        if f == F_DEL:
            return i, False
        if f == F_END:
            return i, True
    raise SystemExit("p8xfs: directory full")


# ---- v2 hierarchical directory machinery ------------------------------------
def version(img):
    return img[BOOT_LBA * SEC + 2]


def dir_secs(entry):
    """Sectors occupied by a directory extent (from its length field)."""
    return max(1, entry["length"] // SEC)


def iter_dir(img, dlba, dsecs):
    """Yield live/deleted entries of a directory extent, stopping at $00."""
    for i in range(dsecs * ENT_PER_SEC):
        e = unpack_at(img, ent_abs(dlba, i))
        if e["flags"] == F_END:
            return
        e["index"] = i
        yield e


def name12(name):
    return name.upper().encode("ascii", "replace")[:12].ljust(12, b" ")


def find_in_dir(img, dlba, dsecs, name):
    want = name12(name)
    for e in iter_dir(img, dlba, dsecs):
        if e["flags"] != F_DEL and e["name"] == want:
            return e
    return None


def resolve_dir(img, path):
    """Walk a (possibly absolute) directory path -> (start_lba, sectors).
    All paths here are absolute from root; '.'/'..' resolve via the on-disk
    entries (so they work like everywhere else)."""
    cur = (ROOT_LBA, ROOT_SECS)
    for comp in [c for c in path.strip("/").split("/") if c]:
        e = find_in_dir(img, cur[0], cur[1], comp)
        if e is None:
            raise SystemExit("p8xfs: no such directory: %s" % comp)
        if e["flags"] != F_DIR:
            raise SystemExit("p8xfs: not a directory: %s" % comp)
        cur = (e["start"], dir_secs(e))
    return cur


def split_path(path):
    """'/a/b/name' -> ('/a/b', 'NAME').  'name' -> ('', 'NAME')."""
    p = path.strip("/")
    parent, _, leaf = p.rpartition("/")
    return parent, leaf.upper()


def alloc(img, nsec):
    """Allocate nsec contiguous sectors at the free pointer; zero + return."""
    start = get_free(img)
    for s in range(nsec):
        sec(img, start + s)[:] = b"\x00" * SEC
    set_free(img, start + nsec)
    return start


def add_entry(img, dlba, dsecs, name, start, length, load, exec_, flags):
    """Write a new entry into the first free/$FF slot of a directory extent."""
    for i in range(dsecs * ENT_PER_SEC):
        f = img[ent_abs(dlba, i) + 24]
        if f in (F_END, F_DEL):
            pack_at(img, ent_abs(dlba, i), name, start, length, load, exec_, flags)
            return i
    raise SystemExit("p8xfs: directory %d full" % dlba)


def init_dir_extent(img, dlba, dsecs, parent_lba, parent_secs):
    """Lay down a fresh directory extent: entry 0 = '.', entry 1 = '..'."""
    for s in range(dsecs):
        sec(img, dlba + s)[:] = b"\x00" * SEC
    pack_at(img, ent_abs(dlba, 0), ".",  dlba,       dsecs * SEC,        0, 0, F_DIR)
    pack_at(img, ent_abs(dlba, 1), "..", parent_lba, parent_secs * SEC,  0, 0, F_DIR)


def require_v2(img):
    if version(img) != 2:
        raise SystemExit("p8xfs: not a v2 (hierarchical) volume")


# ---- commands ---------------------------------------------------------------
def cmd_create(a):
    if a.v2:
        nsec = max(a.sectors, DATA_V2)
        img = bytearray(b"\x00" * (nsec * SEC))
        b = sec(img, BOOT_LBA)
        b[0:2] = b"P8"
        b[2] = 2                   # version 2 (hierarchical)
        b[3] = 0                   # OSCNT = 0
        struct.pack_into("<H", img, 4, DATA_V2)        # free pointer
        init_dir_extent(img, ROOT_LBA, ROOT_SECS, ROOT_LBA, ROOT_SECS)  # '..' -> self
        write_img(a.img, img)
        print("created %s (v2): %d sectors, root@LBA %d, free@LBA %d" %
              (a.img, nsec, ROOT_LBA, DATA_V2))
        return
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
    if version(img) == 2:
        dest = a.name or os.path.basename(a.file)
        parent, leaf = split_path(dest)
        pdir = resolve_dir(img, parent)
        if find_in_dir(img, pdir[0], pdir[1], leaf):
            raise SystemExit("p8xfs: %s already exists" % leaf)
        nsec = max(1, math.ceil(len(data) / SEC))
        start = alloc(img, nsec)
        for s in range(nsec):
            sec(img, start + s)[:] = data[s * SEC:(s + 1) * SEC].ljust(SEC, b"\x00")
        add_entry(img, pdir[0], pdir[1], leaf, start, len(data), a.load, a.exec, F_FILE)
        write_img(a.img, img)
        print("put %s  %d bytes  LBA %d..%d" %
              (dest, len(data), start, start + nsec - 1))
        return
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
    if version(img) == 2:
        parent, leaf = split_path(a.name)
        pdir = resolve_dir(img, parent)
        e = find_in_dir(img, pdir[0], pdir[1], leaf)
        if e is None or e["flags"] != F_FILE:
            raise SystemExit("p8xfs: %s not found" % a.name)
    else:
        want = name12(a.name)
        e = next((x for x in (unpack_entry(img, i) for i in
                  range(DIR_SECS * ENT_PER_SEC)) if x["flags"] != F_END
                  and x["flags"] == F_FILE and x["name"] == want), None)
        if e is None:
            raise SystemExit("p8xfs: %s not found" % a.name)
    data = bytes(img[e["start"] * SEC: e["start"] * SEC + e["length"]])
    out = a.out or os.path.basename(a.name)
    write_img(out, bytearray(data))
    print("get %s -> %s (%d bytes)" % (a.name, out, e["length"]))


def _print_dir(img, entries):
    print("%-12s %7s  %-9s %s" % ("NAME", "BYTES", "LBA", "LOAD/EXEC"))
    n = 0
    for e in entries:
        if e["flags"] == F_DEL:
            continue
        nm = e["name"].decode("latin1").rstrip()
        if nm in (".", ".."):
            continue
        kind = "<DIR>" if e["flags"] == F_DIR else ""
        print("%-12s %7d  %-9d %04X/%04X %s" % (
            nm, e["length"], e["start"], e["load"], e["exec"], kind))
        n += 1
    print("%d entr%s" % (n, "y" if n == 1 else "ies"))


def cmd_ls(a):
    img = read_img(a.img)
    print("Volume %s  version %d  OSCNT %d  free@LBA %d" %
          (a.img, version(img), get_oscnt(img), get_free(img)))
    if version(img) == 2:
        dlba, dsecs = resolve_dir(img, a.path or "/")
        _print_dir(img, iter_dir(img, dlba, dsecs))
        return
    _print_dir(img, (unpack_entry(img, i) for i in range(DIR_SECS * ENT_PER_SEC)
                     if unpack_entry(img, i)["flags"] != F_END))


def cmd_mkdir(a):
    img = read_img(a.img)
    require_v2(img)
    parent, leaf = split_path(a.path)
    pdir = resolve_dir(img, parent)
    if find_in_dir(img, pdir[0], pdir[1], leaf):
        raise SystemExit("p8xfs: %s already exists" % leaf)
    newlba = alloc(img, SUBDIR_SECS)
    init_dir_extent(img, newlba, SUBDIR_SECS, pdir[0], pdir[1])
    add_entry(img, pdir[0], pdir[1], leaf, newlba, SUBDIR_SECS * SEC, 0, 0, F_DIR)
    write_img(a.img, img)
    print("mkdir %s  (extent LBA %d..%d)" % (a.path, newlba, newlba + SUBDIR_SECS - 1))


def cmd_tree(a):
    img = read_img(a.img)
    require_v2(img)

    def walk(dlba, dsecs, prefix):
        for e in iter_dir(img, dlba, dsecs):
            if e["flags"] == F_DEL:
                continue
            nm = e["name"].decode("latin1").rstrip()
            if nm in (".", ".."):
                continue
            if e["flags"] == F_DIR:
                print(prefix + nm + "/")
                walk(e["start"], dir_secs(e), prefix + "  ")
            else:
                print(prefix + nm)

    print("/")
    walk(ROOT_LBA, ROOT_SECS, "  ")


def fsck_v2(img, imgname):
    total = len(img) // SEC
    errs = []
    if bytes(img[0:2]) != b"P8":
        errs.append("bad boot signature %r (want 'P8')" % bytes(img[0:2]))
    free = get_free(img)
    extents = []          # (start, sectors, label) for files AND dir extents
    ndirs = nfiles = ndel = 0

    def visit(dlba, dsecs, parent_lba, path):
        nonlocal ndirs, nfiles, ndel
        extents.append((dlba, dsecs, path + "/"))
        # '..' must point at the parent
        up = find_in_dir(img, dlba, dsecs, "..")
        if up and up["start"] != parent_lba:
            errs.append("%s/..: points at LBA %d, parent is %d" %
                        (path, up["start"], parent_lba))
        for e in iter_dir(img, dlba, dsecs):
            nm = e["name"].decode("latin1").rstrip()
            if e["flags"] == F_DEL:
                ndel += 1
                continue
            if nm in (".", ".."):
                continue
            secs = max(1, (e["length"] + SEC - 1) // SEC)
            if e["flags"] == F_DIR:
                ndirs += 1
                visit(e["start"], dir_secs(e), dlba, path + "/" + nm)
            elif e["flags"] == F_FILE:
                nfiles += 1
                extents.append((e["start"], secs, path + "/" + nm))

    visit(ROOT_LBA, ROOT_SECS, ROOT_LBA, "")
    for s, n, label in extents:
        if label != "/" and s < DATA_V2 and label.strip("/"):
            # root extent is the only one allowed below DATA_V2
            if s != ROOT_LBA:
                errs.append("%s: start LBA %d below first data LBA %d" % (label, s, DATA_V2))
        if s + n > total:
            errs.append("%s: extent %d..%d past volume end %d" % (label, s, s + n - 1, total))
    data_ext = sorted((s, n, l) for s, n, l in extents if s >= DATA_V2)
    for (s1, n1, l1), (s2, n2, l2) in zip(data_ext, data_ext[1:]):
        if s1 + n1 > s2:
            errs.append("overlap: %s (%d..%d) and %s (%d..%d)" %
                        (l1, s1, s1 + n1 - 1, l2, s2, s2 + n2 - 1))
    used = sum(n for s, n, _ in data_ext)
    hi = max((s + n for s, n, _ in data_ext), default=DATA_V2)
    if free < hi:
        errs.append("free pointer %d < end of last extent %d" % (free, hi))
    leaked = (free - DATA_V2) - used

    print("Volume %s (v2): %d dir(s), %d file(s), %d deleted slot(s)" %
          (imgname, ndirs, nfiles, ndel))
    print("  free pointer LBA %d, %d data sector(s) used, %d reclaimable by PACK"
          % (free, used, max(0, leaked)))
    if errs:
        for e in errs:
            print("  FAIL: " + e)
        raise SystemExit(1)
    print("  OK")


def cmd_fsck(a):
    img = read_img(a.img)
    if version(img) == 2:
        fsck_v2(img, a.img)
        return
    total = len(img) // SEC
    errs = []
    if bytes(img[0:2]) != b"P8":
        errs.append("bad boot signature %r (want 'P8')" % bytes(img[0:2]))
    free = get_free(img)

    # Collect live extents (flag $01) as (start, sectors, name).
    live = []
    ndel = 0
    for i in range(DIR_SECS * ENT_PER_SEC):
        e = unpack_entry(img, i)
        if e["flags"] == F_END:
            break
        if e["flags"] == F_DEL:
            ndel += 1
            continue
        if e["flags"] != F_FILE:
            continue
        nm = e["name"].decode("latin1").rstrip()
        secs = max(1, (e["length"] + SEC - 1) // SEC)
        s, end = e["start"], e["start"] + secs
        if s < DATA_LBA:
            errs.append("%s: start LBA %d below first data LBA %d" % (nm, s, DATA_LBA))
        if end > total:
            errs.append("%s: extent %d..%d runs past volume end %d" % (nm, s, end - 1, total))
        live.append((s, secs, nm))

    # Overlap check (sort by start LBA).
    live.sort()
    for (s1, n1, nm1), (s2, n2, nm2) in zip(live, live[1:]):
        if s1 + n1 > s2:
            errs.append("overlap: %s (%d..%d) and %s (%d..%d)" %
                        (nm1, s1, s1 + n1 - 1, nm2, s2, s2 + n2 - 1))

    used = sum(n for _, n, _ in live)
    hi = max((s + n for s, n, _ in live), default=DATA_LBA)
    if free < hi:
        errs.append("free pointer %d < end of last extent %d" % (free, hi))
    # Sectors between DATA_LBA and the free pointer that no live file occupies
    # are leaked by DEL and reclaimable by PACK.
    leaked = (free - DATA_LBA) - used

    print("Volume %s: %d live file(s), %d deleted slot(s)" % (a.img, len(live), ndel))
    print("  free pointer LBA %d, %d data sector(s) used, %d reclaimable by PACK"
          % (free, used, max(0, leaked)))
    if errs:
        for e in errs:
            print("  FAIL: " + e)
        raise SystemExit(1)
    print("  OK")


def main():
    p = argparse.ArgumentParser(prog="p8xfs", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("create"); c.add_argument("img")
    c.add_argument("--sectors", type=int, default=256)
    c.add_argument("--v2", action="store_true", help="hierarchical (v2) volume")
    c.set_defaults(fn=cmd_create)

    c = sub.add_parser("boot"); c.add_argument("img"); c.add_argument("osimage")
    c.set_defaults(fn=cmd_boot)

    c = sub.add_parser("put"); c.add_argument("img"); c.add_argument("file")
    c.add_argument("--name"); c.add_argument("--load", type=lambda x: int(x, 0), default=0xB000)
    c.add_argument("--exec", type=lambda x: int(x, 0), default=0xB000)
    c.set_defaults(fn=cmd_put)

    c = sub.add_parser("get"); c.add_argument("img"); c.add_argument("name")
    c.add_argument("--out"); c.set_defaults(fn=cmd_get)

    c = sub.add_parser("ls"); c.add_argument("img")
    c.add_argument("path", nargs="?", help="v2: directory to list (default /)")
    c.set_defaults(fn=cmd_ls)

    c = sub.add_parser("mkdir"); c.add_argument("img"); c.add_argument("path")
    c.set_defaults(fn=cmd_mkdir)

    c = sub.add_parser("tree"); c.add_argument("img"); c.set_defaults(fn=cmd_tree)

    c = sub.add_parser("fsck"); c.add_argument("img"); c.set_defaults(fn=cmd_fsck)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
