# P8X Card 6: CompactFlash/IDE Interface — and P8X/OS, a Minimal Disk Operating System

Extends the P8X five-card design with mass storage and a small ROM-resident operating system. CF is the ideal choice here: in **True IDE mode** a CompactFlash card *is* an ATA drive, and critically, CF supports an **8-bit data transfer mode** — so it bolts onto the P8X's 8-bit bus with about five chips and no 16-bit latching gymnastics.

---

## 1. Card 6: CF/IDE Hardware

### 1.1 How CF maps onto the P8X bus

CF in True IDE mode exposes the standard ATA task-file registers: 3 address lines, two chip selects, read/write strobes, 8/16-bit data. We map it into the I/O page:

| Address | ATA register (CS0 block) |
|---|---|
| $FF10 | Data |
| $FF11 | Error (rd) / Feature (wr) |
| $FF12 | Sector Count |
| $FF13 | LBA 0 (7:0) |
| $FF14 | LBA 1 (15:8) |
| $FF15 | LBA 2 (23:16) |
| $FF16 | LBA 3 (27:24) + drive/LBA-mode bits |
| $FF17 | Status (rd) / Command (wr) |

To the CPU these are just memory locations — `LDA $FF17` reads drive status. No microcode changes, no new control-word bits.

### 1.2 Circuit

- **CF socket** (or, much friendlier for prototyping: a CF-to-40-pin-IDE adapter board, ~$5, brings everything to 0.1" headers)
- **True IDE mode strap**: ground the card's -OE/ATA SEL pin at power-up
- **Select decode**: the I/O-page detector (7430 on A8–A15, same as the I/O card — or share that card's 74138) + A4 region decode → -CS0 for $FF10–$FF17. -CS1 (alternate status block) optional at $FF18–$FF1F
- **A0–A2** from the address bus direct to the CF
- **-IORD**: card-selected ∧ (DOE = MEM) ∧ CLK̄
- **-IOWR**: card-selected ∧ (DLD = MEMW) ∧ CLK̄
- **74245** between D0–D7 and the CF data lines (direction from the read/write decode)
- **-RESET** from backplane RES̄; pull-ups on -IORDY etc. per the CF spec; LED on the activity-friendly status if you like blinkenlights

**BOM: ≈ 5 chips** (74245, 7430 or shared, 74138, 2× gate packages) + socket/adapter.

### 1.3 The 8-bit mode gotcha (read this twice)

After reset, issue **SET FEATURES** (command $EF) with Feature = $01 to enable 8-bit data transfers; thereafter every Data-register access moves one byte and a sector is 512 reads of $FF10.

**Caveat:** 8-bit mode was dropped from later ATA specs, and *some* modern CF cards ignore it. SanDisk cards and industrial-grade CF are the safe choices — this is well-trodden ground in the homebrew community (RC2014, P112, N8VEM all use this trick). Buy two or three candidate cards.

**Fallback if a card refuses 8-bit mode (+2 chips):** read D0–7 directly while latching D8–15 into a 74374; a second read of a latch address returns the high byte. Write path mirrors with a 74373. Works with any card, slightly uglier driver.

### 1.4 Timing
PIO Mode 0 wants ≥165 ns strobes and ~600 ns cycles. At 2 MHz the CLK̄-gated strobe is 250 ns, and consecutive Data-register accesses are separated by instruction overhead anyway — no wait states needed. Polled I/O only (check BSY/DRQ in the Status register); no IRQ or DMA required.

---

## 2. P8X/OS Design

A two-stage system: a permanent **BIOS in EEPROM**, and the **OS proper loaded from CF into RAM** at boot — so you iterate on the OS by writing sectors from the shell (or popping the CF into your Mac), not by pulling and reburning the EEPROM every time.

### 2.1 Memory map (revised)

| Range | Contents |
|---|---|
| $0000–$1FFF | BIOS ROM: drivers, boot loader, syscall jump table |
| $1100–$3FFF | ROM: erased ($FF) — monitor + BIOS end ~$1100 (BASIC is no longer ROM-resident) |
| $4000–$9D46 | OS RAM: P8X/OS kernel + shell, **loaded from CF to $4000 (rev D)**. ~7 KB today; can grow to the boot ceiling at $9D47 (~23.8 KB) or the on-disk OS region (LBA 1–32 = 16 KB), whichever is smaller — so **16 KB max**, up from ~7 KB when it loaded at $8000 |
| $9D47–$9D49 | CF LBA, 24-bit little-endian (LBA0/LBA1/LBA2; fixed by the BIOS). LBA1/LBA2 default 0 after CFINIT — set them for sectors >255 |
| $9E00–$9FFF | Sector buffer SBUF (512 bytes, fixed by the BIOS) |
| $A000–$AFFF | OS variables (relocated above SBUF; ~3.5 KB) |
| $B000–$FDFF | **TPA** — transient program area (~20 KB; RUN load addr + `>` capture) |
| $FE00–$FEFF | Stack page (P3, grows down from $FEFF) |
| $FF00–$FFFF | I/O |

### 2.2 Layer 1 — BIOS (in ROM, ~1.5 KB)

Fixed **jump table at $0100** so user programs and the OS call stable entry points forever, regardless of BIOS revisions:

| Vector | Call | Interface |
|---|---|---|
| $0100 | CONIN | wait, char → A |
| $0103 | CONOUT | A → serial |
| $0106 | CONST | console status → Z flag |
| $0109 | CFINIT | reset drive, SET FEATURES 8-bit, returns C=error |
| $010C | CFREAD | LBA in OS variables, sector → buffer at (P1) |
| $010F | CFWRITE | inverse |
| $0112 | PUTS | print string at (P1)+ until $00 |
| $0115 | PHEX8 | A → two hex digits |
| $0118 | FFIND | find file FNAME in current dir → LBA+FLEN; C=0 found |
| $011B | FCREATE | create file FNAME from FSRC/FLEN; C=1 err |
| $011E | FDELETE | tombstone file FNAME; C=1 not found |
| $0121 | FCOMMIT | register a streamed file (entry + free); C=1 full |
| $0124 | FOPEN | open file FNAME for reading (P1=buf); C=1 missing |
| $0127 | FGETB | next byte → A; C=1 at EOF |
| $012A | FWOPEN | open a write stream at the free pointer (uses SBUF) |
| $012D | FPUTB | append byte A to the write stream |
| $0130 | FCLOSE | flush + register file FNAME; C=1 full |
| $0133 | FRESOLVE | resolve path (P1) → dir extent + leaf FNAME; C=1 bad |
| $0136 | FNORM | copy string (P1) → FNAME, upcased + space-padded to 12 |
| $0139 | FOPENDIR | begin iterating directory at path (P1); C=1 bad path |
| $013C | FNEXT | next live entry → FNAME/FFLAG/LBA/FLEN; C=1 at end |
| $013F | FLOADAT | read FLEN bytes from LBA into (P1) (whole sectors) |
| $0142 | FOPENDIRAT | iterate dir at 16-bit LBA = A (low) + LBA1 $9D48 (high) |
| $0145 | FSDIRBUF | point FNEXT's sector buffer at page A (call after FOPENDIR) |

The table is **append-only** — entries are never reordered or removed, so every OS image on every card keeps working across BIOS revisions. (The directory-iteration calls `FOPENDIRAT`/`FNEXT` carry a full 16-bit LBA, so directories may live anywhere on the volume, not just below sector 256.)

The inner read loop shows the pointer bank earning its keep — B counts 256 twice (or use a RAM counter), P1 walks the buffer:

```
CFRD1:  LDA  $FF17        ; status
        AND  #$08         ; DRQ?
        JZ   CFRD1
        LDA  $FF10        ; data byte
        STA  (P1)+        ; buffer, post-increment
        DEC  B
        JNZ  CFRD1
        ...               ; second 256, then check ERR bit
```

### 2.3 Layer 2 — Boot

1. Reset → BIOS init (ACIA, CFINIT)
2. Read LBA 0; check signature bytes `P8` at offset 0
3. Boot block says: load N sectors starting at LBA 1 → $4000 (rev D; was $8000)
4. JMP $4000 — OS is running
5. No card / bad signature → fall back to the ROM monitor prompt (machine is always usable)

### 2.4 Layer 3 — Filesystem: P8XFS

Deliberately CP/M-grade, not FAT-grade. Contiguous allocation — trivial to
implement, trivial to fsck by eye in a hex dump. The layout is **P8XFS v2**
(hierarchical; the flat v1 has been retired — see
[p8xfs-v2-hierarchical.md](p8xfs-v2-hierarchical.md)):

| LBA | Contents |
|---|---|
| 0 | Boot block: `P8`, version (2), OSCNT, free-space pointer |
| 1–32 | OS image (up to 16 KB) |
| 33–36 | Root directory: 4-sector extent (entry 0 `.`, entry 1 `..`) |
| 37+ | Files + subdirectory extents, contiguous (from the free pointer) |

**Directory entry (32 bytes):** filename 12 (ASCII, space-padded) · start LBA 4 · length in bytes 4 · load address 2 · exec address 2 · flags 1 · spare 7.

Files are allocated at the free pointer and grow it; deletion marks the entry dead; a `PACK` command compacts when the card fragments (it's flash — copying a few MB takes seconds). With sector counts this small, 16-bit LBA arithmetic in A/B with the pointers handling buffer addresses is all very comfortable for the instruction set we defined.

**Mac interchange:** rather than implementing FAT16 on the P8X, do it from the other side — a ~50-line Python script on the MacBook (USB CF reader, raw device access) that reads/writes P8XFS images: `p8xfs put hello.bin`, `p8xfs ls`, `p8xfs get`. You get full interop for 1% of the effort of a FAT driver. (FAT16 read-only on-target is a fine v2 stretch goal: ~2 KB of assembly.)

### 2.5 Layer 4 — Shell (~2 KB, loaded from CF)

Serial command line at 9600 8N1:

(Authoritative command reference: [os/README.md](../../os/README.md).)

```
/> DIR [path]             list a directory
/> CD path                change directory (/abs, rel, .., .)
/> PWD                    print the working directory
/> TREE                   indented listing of the whole tree (v2)
/> MKDIR path             create a subdirectory (v2)
/> RMDIR path             remove an empty subdirectory (v2)
/> CAT path               print a file
/> LOAD GAME.BIN          → load address from dir entry
/> RUN GAME.BIN           load + JSR exec address
/> SAVE DUMP.BIN A000 C000 save memory range
/> DEL  OLD.BIN
/> DUMP A000              hex/ASCII display
/> DEP  A000 3E 41 ...    deposit bytes
/> PACK                   compact free space
/> FSCK                   check filesystem integrity (read-only)
/> EXIT                   return to the ROM monitor
/> cmd >FILE              redirect a command's output to a file
```

Programs return to the shell with RTS (shell calls via JSR) and may call any BIOS vector. That convention — fixed entry table + TPA + RTS-to-shell — is the CP/M model, and it's all the "OS contract" a machine like this needs.

### 2.6 Sizing reality check

| Component | Est. size |
|---|---|
| BIOS + boot | 1.5 KB ROM |
| Kernel/FS | 2 KB RAM |
| Shell | 2 KB RAM |
| ROM monitor (fallback) | 1 KB ROM |

Comfortably inside the maps above, with the whole 23.5 KB TPA left for programs — Tiny BASIC or a Forth loaded *from the CF card* as ordinary executables rather than burned into ROM.

---

## 3. Development Order

1. Card 6 hardware; verify you can read the Status register from the ROM monitor ($FF17 should show RDY)
2. CFINIT + IDENTIFY DEVICE ($EC) — dump the 512-byte ID sector to serial; confirms 8-bit mode end-to-end and prints the card's model string as a victory lap
3. CFREAD/CFWRITE single sectors from the monitor
4. Write the Mac-side `p8xfs` Python tool; format a card image
5. Boot loader → load and jump to a "Hello from RAM" stage 2
6. Shell commands incrementally: DIR → LOAD/RUN → SAVE/DEL → PACK
7. Then the fun part: BASIC and Forth become *files*, and the machine is self-hosting for everyday use
