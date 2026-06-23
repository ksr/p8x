# P8XFS v2 — Hierarchical Filesystem for P8X/OS

**P8XFS v2 is the only filesystem format** — the original flat v1 has been
retired (the monitor `F`, the OS `FORMAT`, and `p8xfs.py` all produce v2). v2
adds subdirectories while keeping the property that made the flat layout
buildable: **contiguous allocation, one extent per file**. The trick that keeps hierarchy cheap is the oldest one in the book:
**a directory is just a file** whose contents are 32-byte entries and whose
flag byte says "directory."

---

## 1. On-Disk Format

### 1.1 Volume layout

| LBA | Contents |
|---|---|
| 0 | Boot block (signature 'P8', version=2, OSCNT, free pointer) |
| 1–32 | OS image (up to 16 KB) |
| 33–36 | **Root directory** (4 sectors = 64 entries) |
| 37+ | Files and subdirectories, contiguous extents |

### 1.2 Directory entry (32 bytes — same shape as v1)

| Offset | Size | Field |
|---|---|---|
| 0–11 | 12 | Name, ASCII, space-padded. '/' forbidden in names |
| 12–15 | 4 | Start LBA |
| 16–19 | 4 | Length in bytes (for a directory: allocated size) |
| 20–21 | 2 | Load address (files only) |
| 22–23 | 2 | Exec address (files only) |
| 24 | 1 | **Flags**: $00 = end-of-directory marker, $01 = file, $02 = directory, $FF = deleted |
| 25–31 | 7 | Spare |

The $00 flag doubles as an end-of-scan terminator (entries are allocated
front-to-back), which keeps directory scans short — you stop at the first
$00 instead of always reading every sector.

### 1.3 Subdirectories

- Created as ordinary extents, default **4 sectors = 64 entries** (a CONFIG
  equate; bump it if you find yourself filling directories)
- **Entry 0 is `.` and entry 1 is `..`**, both flagged $02, pointing at self
  and parent respectively. Root's `..` points at root
- All remaining entries zeroed at MKDIR ($00 = end marker immediately)

The `..` entries are what make relative navigation and the prompt path cheap
on an 8-bit machine: CD just follows LBAs, never re-derives anything.

---

## 2. Path Resolution

Syntax: `/BIN/UTILS/DUMP.BIN` (absolute) or `UTILS/DUMP.BIN` (relative to
the current directory). Case: shell upcases everything on input.

Algorithm (one shared sector buffer, no recursion needed):

```
resolve(path):
  cur = (path starts with '/') ? ROOT : CWD
  for each component split on '/':
      scan entries of cur (read sectors of its extent one at a time):
          stop at flag $00; skip flag $FF
          match 12-byte name?
            last component  -> return entry (file or dir, caller checks)
            else            -> must be flag $02; cur = its start LBA
      no match -> error "NOT FOUND"
```

Worst case RAM: the 512-byte sector buffer plus a 64-byte component
scratch — fits the existing $9Dxx variable page. Estimated kernel growth:
**~1.5–2 KB**, still comfortably inside the $8000–$8FFF kernel region.

### 2.1 OS state

| Variable | Purpose |
|---|---|
| CWDLBA (4) | Start LBA of current directory |
| CWDPATH (64) | Maintained textual path for the prompt, updated by CD |

Prompt becomes: `/BIN/UTILS> `

---

## 3. Shell Changes

New commands:

```
MKDIR name        create subdirectory in CWD (allocates 4-sector extent,
                  writes . and .. entries)
CD path           change directory ("CD /", "CD ..", "CD BIN/UTILS")
RMDIR name        remove directory — refused unless empty
                  (scan finds nothing but ., .., $FF, $00)
DIR [path]        now takes an optional path; directories listed as <DIR>
TREE              optional treat: depth-first listing with indentation —
                  ~30 lines of code given resolve() exists
```

Changed behavior: **every command that takes a filename now accepts a
path** — `RUN /BIN/FORTH.BIN`, `SAVE /SRC/TEST.BIN B000 B400`, `DEL
OLD/JUNK.BIN`. The parser change is in exactly one place (resolve), which
is the payoff of doing it this way.

---

## 4. The PACK Problem (read before implementing)

Contiguous allocation + deletions still needs compaction, but moving an
extent now has bookkeeping:

1. Moving a **file**: update the start LBA in its *parent's* entry (you must
   know the parent — see walk below).
2. Moving a **directory**: update the parent's entry, **and** rewrite the
   moved directory's own `.` entry, **and** rewrite the `..` entry of every
   *child* directory inside it.

The clean implementation is a **depth-first tree walk from root**, copying
extents downward in address order and fixing pointers as you go — the walk
naturally has the parent in hand when it processes each child, so all three
updates fall out of the traversal. Keep a small explicit stack of
(dir LBA, entry index) pairs in RAM — depth 8 is plenty (a CONFIG limit on
path depth keeps this bounded and also caps CWDPATH).

PACK is the most intricate routine in the OS. Write it last, test it on a
scratch card, and have the Mac-side tool able to verify a volume (§6).

---

## 5. Format & Boot Changes

- Boot block version byte = 2; the monitor's B command doesn't care (it only
  reads signature + OSCNT), so **the ROM does not change**
- Formatting: **done as an OS-level `FORMAT` command** (P8X/OS, since the OS moved
  to $4000 and had room). It writes the v2 boot block (version 2, free = 37) and a
  fresh root extent at LBA 33 (4 sectors, `.`/`..`), preserving OSCNT so the card
  stays bootable. The monitor's `F` still writes a **v1** volume — policy for v2
  lives on disk where it's cheap to change, and the monitor stays frozen.
- v1→v2 migration: none. Reformat and re-copy via the Mac tool — at these
  volume sizes that's a 10-second operation

## 6. Mac-Side Tool (p8xfs.py) Updates

- `ls [path]`, `put file [/dir/...]`, `get /path/file`, `mkdir /path`,
  `tree`, plus `fsck`: verify every extent lies inside the volume, no
  extents overlap, every `..` points at the true parent, free pointer ≥ end
  of last extent. Having fsck on the Mac side before PACK exists on-target
  is the right safety order

## 7. Deliberate Non-Features (v3 candidates)

- **Growable directories**: an over-full directory currently requires
  "allocate bigger, copy, repoint parent" — implementable later as RESIZE
- **FAT-style cluster chains**: would eliminate PACK and fixed-size
  directories at the cost of an allocation table and linked traversal on
  every read. The right move if the machine becomes a daily driver; overkill
  for now. The entry format above is deliberately compatible with that
  future (start LBA becomes first-cluster)
- Timestamps (no RTC — a DS1302 on the I/O card someday), permissions,
  long names
