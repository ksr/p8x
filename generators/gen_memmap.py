#!/usr/bin/env python3
"""gen_memmap.py - single source of truth for the P8X data memory map.

Emits three views of ONE table so firmware, the OS, the emulator, and the compiler
toolchain stop hand-copying (and copy-drifting) the same addresses:
  generators/memmap.inc  (asm equates)  -> .include'd by firmware / os / p8xcc
  generators/memmap.h    (C #defines)   -> #include'd by the emulator
  generators/memmap.py   (Python)       -> imported by compiler/p8cc.py

Scope: the DATA map - region anchors, I/O ports, every RAM scratch/buffer address.
NOT code-entry vectors (BIOS jump table $01xx, syscall vector $20xx - owned by their
component / named in os/commands/lib_abi.*), nor the file-local temps TMP/TMP2/CNT
(they collide by name across firmware and the OS; see BACKLOG).

Run:  python3 generators/gen_memmap.py
"""
import os

# (section, NAME, value, comment) - THE canonical table. Edit here only, then re-run.
MAP = [
    ('memory-region anchors', 'RAMBASE', 0x2000, 'first RAM address (OS + scratch + TPA live here)'),
    ('memory-region anchors', 'IOBASE', 0xFF00, 'memory-mapped I/O page'),
    ('memory-region anchors', 'ROMSIZE', 0x2000, '8K firmware ROM $0000-$1FFF'),
    ('memory-region anchors', 'RAMSIZE', 0xDF00, 'RAM span $2000-$FEFF (IOBASE-RAMBASE)'),
    ('memory-region anchors', 'OSORG', 0x2000, 'OS load/link address (= RAMBASE)'),
    ('memory-region anchors', 'TPABASE', 0x6100, 'transient program area base (RUNnable programs load here)'),
    ('memory-region anchors', 'CSTACKTOP', 0xF800, 'compiler C-stack top (grows down; p8cc __csp init)'),
    # Resident window-manager kernel: there is NO separate base address any more.
    # It is folded into the OS image (os/p8xos.asm .includes os/wmkernel_body.asm)
    # and reached through the OS syscall table, $2027..$204B (SYS_WKINIT, WKOPEN,
    # WKREPAINT, WKRUN, WKSAVE, WKLOAD, WKPATH, WKEVENT, WKCLOSE, WKARG, WKGET,
    # WKTOP, WKRAISE), so it is always resident from boot and
    # needs no loading. Apps keep the FULL TPA $6A00..CSTACKTOP. (History: a
    # standalone blob lived at $D800 above the TPA, then at $5600 -- both retired;
    # $5600 sat inside the shell history ring, which is why the ring moved.)
    ('I/O ports ($FF00-$FFFF)', 'ACIAS', 0xFF04, 'ACIA status (rd) / control (wr)'),
    ('I/O ports ($FF00-$FFFF)', 'ACIAD', 0xFF05, 'ACIA data'),
    # Second serial port (two-mode P3): a 2nd ACIA, register-identical to the
    # first, for the serial-terminal / Kermit file-transfer command. Emulator
    # backs it with a file pair (-2i RX / -2o TX); real hardware is a 2nd 6850.
    ('I/O ports ($FF00-$FFFF)', 'ACIA2S', 0xFF08, '2nd ACIA status (rd) / control (wr) -- the Kermit/serial-terminal port'),
    ('I/O ports ($FF00-$FFFF)', 'ACIA2D', 0xFF09, '2nd ACIA data'),
    ('I/O ports ($FF00-$FFFF)', 'CFDATA', 0xFF10, 'CF task file'),
    ('I/O ports ($FF00-$FFFF)', 'CFFEAT', 0xFF11, ''),
    ('I/O ports ($FF00-$FFFF)', 'CFSCNT', 0xFF12, ''),
    ('I/O ports ($FF00-$FFFF)', 'CFLBA0', 0xFF13, ''),
    ('I/O ports ($FF00-$FFFF)', 'CFLBA1', 0xFF14, ''),
    ('I/O ports ($FF00-$FFFF)', 'CFLBA2', 0xFF15, ''),
    ('I/O ports ($FF00-$FFFF)', 'CFHEAD', 0xFF16, '$E0 = LBA mode, drive 0'),
    ('I/O ports ($FF00-$FFFF)', 'CFCMD', 0xFF17, 'command (wr) / status (rd)'),
    ('I/O ports ($FF00-$FFFF)', 'CFSTAT', 0xFF17, ''),

    # $FF20-$FF2F: RETIRED (the single-interface migration closed the device
    # door). The window's registers -- GX0..GY1 pairs, GCOL/GCOLH, GCMD,
    # GSTAT, GDATA, GPARM/GPARM2, GMODE, the GID0/GID1 "PG" signature -- are
    # no longer bus-decoded anywhere: the drawing engine survives inside the
    # card as the GL walker's private register file, and the GL port at
    # $FF50 is the ONE graphics interface ('G' at GLID is the presence
    # probe). Reads float $FF like any absent card.

    # Stage 8a: the MDU (multiply-divide unit), $FF30-$FF3F. Hardware muldiv,
    # bit-exact to lib_g3d's software contract (STAGE8-DESIGN.md): q = (a*b)/c
    # signed through a 32-bit intermediate, truncated toward zero, saturated at
    # +/-32767; 0 when a or b is 0 (even with c=0); +/-32767 when c is 0.
    # Operands follow the gfx register conventions: 16-bit pairs, a LOW write
    # CLEARS the high byte, highs sit 9 above their lows. Write MDGO to start,
    # poll MDSTAT bit 7, then read MDQ (the RTL divider is busy ~20 cycles; the
    # emulator computes instantly, the same licence GPU BUSY takes -- so
    # software must still poll). MDID is the presence probe: an absent unit
    # floats the bus to $FF, the same rule as the display's "PG".
    ('I/O ports ($FF00-$FFFF)', 'MDA', 0xFF30, 'MDU operand a, low byte (write clears the high byte)'),
    ('I/O ports ($FF00-$FFFF)', 'MDB', 0xFF31, 'MDU operand b, low byte'),
    ('I/O ports ($FF00-$FFFF)', 'MDC', 0xFF32, 'MDU divisor c, low byte'),
    ('I/O ports ($FF00-$FFFF)', 'MDQ', 0xFF33, 'read: MDU result (a*b)/c, low byte (poll MDSTAT first)'),
    ('I/O ports ($FF00-$FFFF)', 'MDGO', 0xFF34, 'write (any value): start the MDU operation'),
    ('I/O ports ($FF00-$FFFF)', 'MDSTAT', 0xFF35, 'read: bit7 BUSY'),
    ('I/O ports ($FF00-$FFFF)', 'MDID', 0xFF36, "read: $4D 'M' -- MDU-presence probe"),
    # The stage-8b geometry engine's $FF40-$FF4F register window (GESEL/
    # GEVAL/GEUP/GECMD/GESTAT/GEID) is RETIRED as of stage 10b: the GL
    # command port below is the one hardware 3D interface, and the window
    # floats to $FF so lib_g3d's GEID probe falls back to its software
    # walk. History: STAGE8B/9-DESIGN.md; the retirement: STAGE10-DESIGN.md.
    # Stage 10: the GRAPHICS LANGUAGE port, $FF50-$FF57 (STAGE10-DESIGN.md).
    # A PGC-style command stream (Matrox PG-640A manual is the reference):
    # bytes written to GLDATA feed a command FIFO; an interpreter executes
    # opcode + int16-LE parameters (hex mode; ASCII mode arrives stage 10d).
    # The interpreter owns the transform/draw datapath and its parameter
    # file (matrices, window, viewport, focal, near/far planes) -- all
    # state is set by VERBS, never by registers. GLRB/GLERR drain the
    # read-back and error FIFOs (one error byte per fault; codes in the
    # design doc and man gl).
    ('I/O ports ($FF00-$FFFF)', 'GLDATA', 0xFF50, 'GL: write one command-stream byte into the FIFO'),
    ('I/O ports ($FF00-$FFFF)', 'GLSTAT', 0xFF51, 'read: bit7 FIFO full, bit6 busy, bit1 error pending, bit0 read-back pending'),
    ('I/O ports ($FF00-$FFFF)', 'GLRB', 0xFF52, 'read: pop one read-back FIFO byte'),
    ('I/O ports ($FF00-$FFFF)', 'GLERR', 0xFF53, 'read: pop one error FIFO byte (0 = empty)'),
    ('I/O ports ($FF00-$FFFF)', 'GLID', 0xFF54, "read: $47 'G' -- graphics-language presence probe"),

    ('I/O ports ($FF00-$FFFF)', 'MDAH', 0xFF39, 'MDU operand a, high byte (write AFTER MDA)'),
    ('I/O ports ($FF00-$FFFF)', 'MDBH', 0xFF3A, 'MDU operand b, high byte'),
    ('I/O ports ($FF00-$FFFF)', 'MDCH', 0xFF3B, 'MDU divisor c, high byte'),
    ('I/O ports ($FF00-$FFFF)', 'MDQH', 0xFF3C, 'read: MDU result, high byte'),

    ('BIOS / FS scratch ($6000-$60FF)', 'LBUF', 0x6000, 'input line buffer'),
    ('BIOS / FS scratch ($6000-$60FF)', 'ADDRL', 0x6040, 'parsed address'),
    ('BIOS / FS scratch ($6000-$60FF)', 'ADDRH', 0x6041, ''),
    ('BIOS / FS scratch ($6000-$60FF)', 'HEXL', 0x6042, 'hex accumulator'),
    ('BIOS / FS scratch ($6000-$60FF)', 'HEXH', 0x6043, ''),
    ('BIOS / FS scratch ($6000-$60FF)', 'LBA', 0x6047, 'current LBA, byte 0 (bits 7:0)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'LBA1', 0x6048, 'LBA byte 1 (bits 15:8)  — 0 after CFINIT unless set'),
    ('BIOS / FS scratch ($6000-$60FF)', 'LBA2', 0x6049, 'LBA byte 2 (bits 23:16) — 0 after CFINIT unless set'),
    ('BIOS / FS scratch ($6000-$60FF)', 'FNAME', 0x604A, '12-byte filename (space-padded) — in for both calls'),
    ('BIOS / FS scratch ($6000-$60FF)', 'FSRC', 0x6056, 'FCREATE: source address of the file data (2 bytes)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'FLEN', 0x6058, 'file length in bytes (3 bytes): FCREATE in, FFIND out'),
    ('BIOS / FS scratch ($6000-$60FF)', 'FSAV', 0x605B, 'FCREATE scratch: requested length saved across FFIND (3)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'ROLBA', 0x605E, 'next sector LBA to read (3)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'ROREM', 0x6061, 'bytes remaining in the file (3)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'ROBUF', 0x6064, "caller's 512-byte sector buffer address (2)"),
    ('BIOS / FS scratch ($6000-$60FF)', 'ROPTR', 0x6066, 'read cursor within ROBUF (2)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'ROCNT', 0x6068, 'bytes left in ROBUF; 0 -> refill (3)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'WOLBA', 0x606B, 'current output sector LBA (3)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'WOPOS', 0x606E, 'byte offset within SBUF; 512 -> flush (2)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'WOTOT', 0x6070, 'total bytes written (-> FLEN at close) (3)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'DIRLBA', 0x6073, 'current directory start LBA, low byte (16-bit: +DIRLBA1)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'DIRN', 0x6074, 'current directory sector count (1)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'FFLAG', 0x6075, 'flag of the entry FSCAN matched (file $01 / dir $02)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'RPATH', 0x6076, 'FRESOLVE path cursor (2)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'DILBA', 0x6078, 'iteration: current directory sector LBA (1)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'DICNT', 0x6079, 'iteration: sectors remaining (1)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'DIIDX', 0x607A, 'iteration: entry index within the sector (0..15)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'FLAREM', 0x607B, 'FLOADAT remaining-bytes counter (CFRDSEC clobbers TMP) (3)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'DIBUFH', 0x607E, 'FNEXT directory-buffer page (high byte; low byte 0).'),
    ('BIOS / FS scratch ($6000-$60FF)', 'DILBA1', 0x607F, 'FNEXT iteration sector LBA, high byte'),
    ('BIOS / FS scratch ($6000-$60FF)', 'DIRLBA1', 0x6080, 'current directory start LBA, high byte (pairs DIRLBA)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'FCDH', 0x6081, 'FCREATE directory-sector scan cursor, high byte (HEXL)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'DRVSEL', 0x6082, 'current CF drive for sector I/O (0/1); ORed into CFHEAD'),
    ('BIOS / FS scratch ($6000-$60FF)', 'CFTOL', 0x6083, 'CF bounded-wait timeout counter, low byte'),
    ('BIOS / FS scratch ($6000-$60FF)', 'CFTOH', 0x6084, 'CF bounded-wait timeout counter, high byte'),
    ('BIOS / FS scratch ($6000-$60FF)', 'ROSDRV', 0x6085, 'read-stream drive (captured by FOPEN, re-asserted by FG_FILL)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'WOSDRV', 0x6086, 'write-stream drive (captured by FWOPEN, re-asserted by FW_FLUSH)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'CFIMASK', 0x6087, "bit N set = drive N has been CFINIT'd this session"),
    ('BIOS / FS scratch ($6000-$60FF)', 'REMW', 0x6088, 'FCOM_CORE ceil(FLEN/512): 24-bit remaining counter (3)'),
    ('BIOS / FS scratch ($6000-$60FF)', 'CNTW', 0x608B, 'FCOM_CORE sector count, 16-bit (files may span >255 sectors)'),
    ('shared sector buffer', 'SBUF', 0x5E00, 'sector buffer'),
    ('hardware stack', 'STKTOP', 0xFEFF, ''),
    ('BIOS / FS scratch ($6000-$60FF)', 'ROSTAT', 0x605E, 'read-stream state base (ROLBA..ROCNT, 11 bytes)'),
    ('OS scratch ($5900-$5FFF)', 'LINEBUF', 0x5700, 'shell input line (64 bytes)'),
    ('OS scratch ($5900-$5FFF)', 'CMDBUF', 0x5740, 'parsed command word (16 bytes)'),
    ('OS scratch ($5900-$5FFF)', 'NAMEBUF', 0x5750, '12-byte filename (search key / DIR scratch)'),
    ('OS scratch ($5900-$5FFF)', 'ECNT', 0x5763, 'entries-left-in-sector counter'),
    ('OS scratch ($5900-$5FFF)', 'FLAGS', 0x5764, 'current entry flag byte'),
    ('OS scratch ($5900-$5FFF)', 'MATCH', 0x5765, '1 = name matched / strings equal'),
    ('OS scratch ($5900-$5FFF)', 'LENLO', 0x5766, 'entry length, low 16 bits'),
    ('OS scratch ($5900-$5FFF)', 'LENHI', 0x5767, ''),
    ('OS scratch ($5900-$5FFF)', 'STARTLO', 0x5768, 'entry start LBA (low byte)'),
    ('OS scratch ($5900-$5FFF)', 'LOADLO', 0x5769, 'entry load address'),
    ('OS scratch ($5900-$5FFF)', 'LOADHI', 0x576A, ''),
    ('OS scratch ($5900-$5FFF)', 'EXECLO', 0x576B, 'entry exec address'),
    ('OS scratch ($5900-$5FFF)', 'EXECHI', 0x576C, ''),
    ('OS scratch ($5900-$5FFF)', 'DLBA', 0x576D, 'directory sector being scanned'),
    ('OS scratch ($5900-$5FFF)', 'SECCNT', 0x576E, 'sectors left to transfer'),
    ('OS scratch ($5900-$5FFF)', 'CURLBA', 0x576F, 'current data LBA'),
    ('OS scratch ($5900-$5FFF)', 'ENTPL', 0x5770, 'pointer to a directory entry (in SBUF):'),
    ('OS scratch ($5900-$5FFF)', 'ENTPH', 0x5771, 'flag byte for DEL, entry start for SAVE'),
    ('OS scratch ($5900-$5FFF)', 'ARGPL', 0x5772, 'saved arg position in LINEBUF'),
    ('OS scratch ($5900-$5FFF)', 'ARGPH', 0x5773, ''),
    ('OS scratch ($5900-$5FFF)', 'HXLO', 0x5774, 'GETHEX result'),
    ('OS scratch ($5900-$5FFF)', 'HXHI', 0x5775, ''),
    ('OS scratch ($5900-$5FFF)', 'DIGIT', 0x5776, 'HEXVAL digit value'),
    ('OS scratch ($5900-$5FFF)', 'SHCNT', 0x5777, 'shift counter'),
    ('OS scratch ($5900-$5FFF)', 'SVSTLO', 0x5778, 'SAVE source start address'),
    ('OS scratch ($5900-$5FFF)', 'SVSTHI', 0x5779, ''),
    ('OS scratch ($5900-$5FFF)', 'FREELO', 0x577A, 'boot-block free pointer (next data LBA)'),
    ('OS scratch ($5900-$5FFF)', 'FREEHI', 0x577B, ''),
    ('OS scratch ($5900-$5FFF)', 'SRCLO', 0x577C, 'running source pointer during the copy'),
    ('OS scratch ($5900-$5FFF)', 'SRCHI', 0x577D, ''),
    ('OS scratch ($5900-$5FFF)', 'REM', 0x577E, 'sectors remaining in the SAVE write loop'),
    ('OS scratch ($5900-$5FFF)', 'NF', 0x5780, 'running next-free LBA'),
    ('OS scratch ($5900-$5FFF)', 'PFOUND', 0x5781, '1 if this pass found an unpacked extent'),
    ('OS scratch ($5900-$5FFF)', 'MINSTRT', 0x5782, 'smallest start LBA >= NF this pass'),
    ('OS scratch ($5900-$5FFF)', 'MINSEC', 0x5783, "that extent's sector count"),
    ('OS scratch ($5900-$5FFF)', 'MINPL', 0x5784, "pointer to that entry's start-LBA field (in SBUF)"),
    ('OS scratch ($5900-$5FFF)', 'MINPH', 0x5785, ''),
    ('OS scratch ($5900-$5FFF)', 'MINDL', 0x5786, "that entry's directory sector LBA"),
    ('OS scratch ($5900-$5FFF)', 'ESTART', 0x5787, 'current entry start LBA (low byte)'),
    ('OS scratch ($5900-$5FFF)', 'SRCL', 0x5788, 'copy source LBA'),
    ('OS scratch ($5900-$5FFF)', 'DSTL', 0x5789, 'copy dest LBA'),
    ('OS scratch ($5900-$5FFF)', 'CPYN', 0x578A, 'sectors left to copy'),
    ('OS scratch ($5900-$5FFF)', 'CANDL', 0x578B, "current entry's start-field pointer"),
    ('OS scratch ($5900-$5FFF)', 'CANDH', 0x578C, ''),
    ('OS scratch ($5900-$5FFF)', 'ROOTN', 0x578D, 'root directory sector count (4)'),
    ('OS scratch ($5900-$5FFF)', 'DATABASE', 0x578E, 'first data LBA (37)'),
    ('OS scratch ($5900-$5FFF)', 'CWDL', 0x578F, 'current directory: start LBA'),
    ('OS scratch ($5900-$5FFF)', 'CWDN', 0x5790, 'sector count'),
    ('OS scratch ($5900-$5FFF)', 'SDIRL', 0x5791, 'directory being scanned this op (start LBA)'),
    ('OS scratch ($5900-$5FFF)', 'SDIRN', 0x5792, 'sector count'),
    ('OS scratch ($5900-$5FFF)', 'SCNT', 0x5793, 'sectors-left counter while scanning a directory'),
    ('OS scratch ($5900-$5FFF)', 'LSL', 0x5794, "SETPATH: pointer to the last '/' in CWDPATH"),
    ('OS scratch ($5900-$5FFF)', 'LSH', 0x5795, ''),
    ('OS scratch ($5900-$5FFF)', 'PATHL', 0x5796, 'saved path cursor across DESCEND (FINDENT clobbers P2)'),
    ('OS scratch ($5900-$5FFF)', 'PATHH', 0x5797, ''),
    ('OS scratch ($5900-$5FFF)', 'NEWLBA', 0x5798, 'MKDIR: LBA of the new directory extent'),
    ('OS scratch ($5900-$5FFF)', 'PSL', 0x5799, 'MKDIR: parent dir start LBA / sector count'),
    ('OS scratch ($5900-$5FFF)', 'PSN', 0x579A, ''),
    ('OS scratch ($5900-$5FFF)', 'EFLAG', 0x579B, 'flag byte WRENT stamps (F_FILE for SAVE, F_DIR for MKDIR)'),
    ('OS scratch ($5900-$5FFF)', 'RMDL', 0x579C, 'RMDIR: parent directory sector holding the entry'),
    ('OS scratch ($5900-$5FFF)', 'CDST', 0x579D, 'current directory: start LBA / sectors / entry index'),
    ('OS scratch ($5900-$5FFF)', 'CDSC', 0x579E, ''),
    ('OS scratch ($5900-$5FFF)', 'CIDX', 0x579F, ''),
    ('OS scratch ($5900-$5FFF)', 'REDIRF', 0x57A0, '0 = console, 1 = capturing to RBUF'),
    ('OS scratch ($5900-$5FFF)', 'RCH', 0x57A1, 'OUTCH: byte being emitted'),
    ('OS scratch ($5900-$5FFF)', 'RS2L', 0x57A2, 'OUTCH: saved caller P2'),
    ('OS scratch ($5900-$5FFF)', 'RS2H', 0x57A3, ''),
    ('OS scratch ($5900-$5FFF)', 'RPTRL', 0x57A4, 'OUTCH: next free byte in the capture buffer'),
    ('OS scratch ($5900-$5FFF)', 'RPTRH', 0x57A5, ''),
    ('OS scratch ($5900-$5FFF)', 'RHX', 0x57A6, 'OPHEX8 scratch'),
    ('OS scratch ($5900-$5FFF)', 'REDNAME', 0x57A7, 'redirect target filename (null-terminated, <=48): $63A7..$63D6'),
    ('OS scratch ($5900-$5FFF)', 'FNDIR', 0x57D7, 'directories counted'),
    ('OS scratch ($5900-$5FFF)', 'FNFIL', 0x57D8, 'files counted'),
    ('OS scratch ($5900-$5FFF)', 'FNDEL', 0x57D9, 'deleted slots counted'),
    ('OS scratch ($5900-$5FFF)', 'FMAXE', 0x57DA, 'highest extent end LBA seen (data area only)'),
    ('OS scratch ($5900-$5FFF)', 'FUSED', 0x57DB, 'data sectors occupied by live extents'),
    ('OS scratch ($5900-$5FFF)', 'FERR', 0x57DC, 'problems found (0 = clean)'),
    ('OS scratch ($5900-$5FFF)', 'FCHILD', 0x57DD, "CHKDD: directory whose '..' is being checked"),
    ('OS scratch ($5900-$5FFF)', 'FEXP', 0x57DE, 'CHKDD: expected parent LBA'),
    ('TPA (transient programs)', 'RBUF', 0x6100, 'capture buffer = the TPA (free during a built-in cmd)'),
    ('OS scratch ($5900-$5FFF)', 'TSP', 0x57E0, 'tree stack depth (0 = at root level)'),
    ('OS scratch ($5900-$5FFF)', 'TI', 0x57E1, 'scratch loop counter for the frame stack'),
    ('OS scratch ($5900-$5FFF)', 'LENHI2', 0x57E2, 'entry length, bits 16..23 (the BIOS FLEN 3rd byte)'),
    ('OS scratch ($5900-$5FFF)', 'SECCH', 0x57E3, 'SECCOUNT sector-count high byte (files >255 sectors)'),
    ('OS scratch ($5900-$5FFF)', 'MINSECH', 0x57E4, "PACK: chosen extent's sector count, high byte"),
    ('OS scratch ($5900-$5FFF)', 'CPYNH', 0x57E5, 'PK2MOVE: sectors-to-copy counter, high byte'),
    ('OS scratch ($5900-$5FFF)', 'TFRAME', 0x58B7, '8 frames x 4 bytes (dst_lo,dst_hi,dsc,idx): $64B7..$64D6'),
    ('OS scratch ($5900-$5FFF)', 'PPSEC', 0x57FA, "chosen extent's parent-entry: dir sector LBA / slot"),
    ('OS scratch ($5900-$5FFF)', 'PPSLOT', 0x57FB, ''),
    ('OS scratch ($5900-$5FFF)', 'CANDSEC', 0x57FC, "candidate entry's location during the find walk"),
    ('OS scratch ($5900-$5FFF)', 'CANDSLOT', 0x57FD, ''),
    ('OS scratch ($5900-$5FFF)', 'PARST', 0x57FE, "PK2FIX: parent directory start LBA (for '..')"),
    ('OS scratch ($5900-$5FFF)', 'CWDPATH', 0x5800, 'textual CWD path for the prompt (up to 48 bytes)'),
    ('OS scratch ($5900-$5FFF)', 'INMODE', 0x5830, 'SYS_GETC source: 0 = console, 1 = the read stream'),
    ('OS scratch ($5900-$5FFF)', 'INARM', 0x5831, "shell armed a '< file' for the next RUN"),
    ('OS scratch ($5900-$5FFF)', 'INNAME', 0x5832, "'< file' name (null-terminated, <=48): $6432..$6461"),
    ('OS scratch ($5900-$5FFF)', 'PIPEF', 0x5862, 'pipe stage: 0 none, 1 left ran, 2 right ran'),
    ('OS scratch ($5900-$5FFF)', 'PIPEBUF', 0x5863, "saved right-hand command of a 'cmd | cmd' ($6463..$64A2)"),
    ('OS scratch ($5900-$5FFF)', 'CWDLH', 0x58A3, 'CWDL high byte (current working directory start LBA)'),
    ('OS scratch ($5900-$5FFF)', 'SDIRLH', 0x58A4, 'SDIRL high byte (directory being scanned this op)'),
    ('OS scratch ($5900-$5FFF)', 'STARTHI', 0x58A5, 'STARTLO high byte (entry start LBA from FINDENT)'),
    ('OS scratch ($5900-$5FFF)', 'DLBAH', 0x58A6, 'DLBA high byte (directory-sector scan cursor)'),
    ('OS scratch ($5900-$5FFF)', 'NEWLBAH', 0x58A7, 'NEWLBA high byte (MKDIR new extent)'),
    ('OS scratch ($5900-$5FFF)', 'PSLH', 0x58A8, 'PSL high byte (MKDIR parent extent)'),
    ('OS scratch ($5900-$5FFF)', 'PARSTH', 0x58A9, "PARST high byte (PACK '..' parent fix)"),
    ('OS scratch ($5900-$5FFF)', 'RMDLH', 0x58AA, 'RMDL high byte (RMDIR parent sector)'),
    ('OS scratch ($5900-$5FFF)', 'CURLBAH', 0x58AB, 'CURLBA high byte (SAVE data-write LBA, 16-bit)'),
    ('OS scratch ($5900-$5FFF)', 'NFH', 0x58AC, 'NF high byte (PACK next-free target)'),
    ('OS scratch ($5900-$5FFF)', 'MINSTRTH', 0x58AD, 'MINSTRT high byte (smallest start LBA this pass)'),
    ('OS scratch ($5900-$5FFF)', 'CDSTH', 0x58AE, 'CDST high byte (current directory in the walk)'),
    ('OS scratch ($5900-$5FFF)', 'CANDSECH', 0x58AF, "CANDSEC high byte (candidate entry's dir sector)"),
    ('OS scratch ($5900-$5FFF)', 'PPSECH', 0x58B0, "PPSEC high byte (chosen extent's parent-entry sector)"),
    ('OS scratch ($5900-$5FFF)', 'SRCH', 0x58B1, 'SRCL high byte (PK2MOVE copy source)'),
    ('OS scratch ($5900-$5FFF)', 'DSTH', 0x58B2, 'DSTL high byte (PK2MOVE copy dest)'),
    ('OS scratch ($5900-$5FFF)', 'FCHILDH', 0x58B3, 'FCHILD high byte (CHKDD child dir)'),
    ('OS scratch ($5900-$5FFF)', 'FEXPH', 0x58B4, 'FEXP high byte (CHKDD expected parent)'),
    ('OS scratch ($5900-$5FFF)', 'FMAXEH', 0x58B5, 'FMAXE high byte (FSCK highest extent end)'),
    ('OS scratch ($5900-$5FFF)', 'FUSEDH', 0x58B6, 'FUSED high byte (FSCK live data sectors)'),
    ('OS scratch ($5900-$5FFF)', 'REDAPP', 0x58D7, '>> append redirect: 1 = prepend the existing file'),
    ('OS scratch ($5900-$5FFF)', 'APHAVE', 0x58D8, '>> : 1 = an existing file to prepend was found'),
    ('OS scratch ($5900-$5FFF)', 'APLBA', 0x58D9, ">> : old file's start LBA (2 bytes)"),
    ('OS scratch ($5900-$5FFF)', 'APREM', 0x58DB, '>> : old file bytes left to copy (2 bytes)'),
    ('OS scratch ($5900-$5FFF)', 'APCHK', 0x58DD, '>> : bytes to emit from the current sector (2 bytes)'),
    ('OS scratch ($5900-$5FFF)', 'SCRIPTM', 0x58E0, '1 = the shell is running lines from a `sh` script'),
    ('OS scratch ($5900-$5FFF)', 'SCRSAVE', 0x58E1, 'saved script read-stream state (ROSTATE 13 + ROSDRV = 14: $64E1..$64EE)'),
    ('OS scratch ($5900-$5FFF)', 'SCRCNT', 0x58EF, 'byte counter for SAVESCR/RESTSCR (1)'),
    ('OS scratch ($5900-$5FFF)', 'APBUF', 0x5C00, '>> prepend sector buffer (512B, below the TPA); also the'),
    ('OS scratch ($5900-$5FFF)', 'IBUF', 0x5900, '512-byte buffer for the stdin read stream'),
    ('OS scratch ($5900-$5FFF)', 'PATHBUF', 0x5B00, "search path, ';'-separated dirs; default '/BIN' ($6700..$673F)"),
    ('OS scratch ($5900-$5FFF)', 'RUNPATH', 0x5B40, 'scratch: candidate program path built during a lookup ($6740..$679F)'),
    ('OS scratch ($5900-$5FFF)', 'RUNSKIP', 0x5BA0, 'DORUN: 1 = skip the program-name word for the arg pointer'),
    ('OS scratch ($5900-$5FFF)', 'PSCANL', 0x5BA1, 'PATH search cursor into PATHBUF (low)'),
    ('OS scratch ($5900-$5FFF)', 'PSCANH', 0x5BA2, 'PATH search cursor into PATHBUF (high)'),
    ('OS scratch ($5900-$5FFF)', 'GPLF', 0x5BA3, 'SYS_GETC console: 1 = a LF is pending after a CR keypress'),
    ('OS scratch ($5900-$5FFF)', 'CURDRIVE', 0x5BA4, 'derived: 1 if the CWD is under /d1 (drive 1), else 0'),
    ('OS scratch ($5900-$5FFF)', 'DRVINIT', 0x5BA5, "bitmask: bit N set = drive N has been CFINIT'd this session"),
    ('OS scratch ($5900-$5FFF)', 'MPSAV', 0x5BA6, "MNTPFX: saved P2 (2 bytes) while sniffing a 'd1' prefix"),
    # Command-line history (interactive line editor). The ring lives in the ONE
    # free block above CSTACKTOP: 8 slots x 64 bytes = $F800..$F9FF. The rest of
    # that gap is NOT free -- it is the C commands' fixed scratch, defined as
    # #defines in os/commands/lib_*.c rather than as anchors here: $FA00..$FBFF is
    # the FSDIRBUF directory/glob sector page (dir, cat, glob_expand), $FC00..$FDFF
    # is RDBUF (the shared file-read buffer), and $FE00..$FEFF is the P3 stack.
    # (History: 32 slots at $5800..$5FFF inside the "OS growth reserve" -- which
    # was never free either: once the WM kernel was folded into the OS image
    # (ending ~$5B4C then) every typed command line overwrote live kernel code. A first
    # move to 16 slots at $F800..$FBFF then collided with the FSDIRBUF page. Two
    # lessons: grep THIS file for anchors AND the C libs for 0x... literals before
    # calling any region free.) State bytes sit in the free tail of the $6000
    # FS-scratch page (after CNTW).
    ('shell history', 'HISTST', 0x608E, 'history ring: index where the next entry is written (0..HISTN-1)'),
    ('shell history', 'HISTCT', 0x608F, 'history ring: number of stored entries (0..HISTN)'),
    ('shell history', 'HISTNV', 0x6090, 'history ring: recall cursor (0 = not navigating; N = N lines back)'),
    ('shell history', 'HISTRING', 0xF800, 'history ring buffer base: HISTN x HISTLEN bytes ($F800..$F9FF, the free 512 B above CSTACKTOP; $FA00 = glob page, $FC00 = RDBUF, $FE00 = stack)'),
    # Tab autocomplete scratch (interactive line editor). 256 B at the very top of
    # the three completion STRINGS alias the $6800 APBUF region; state bytes in
    # the $6000 FS-scratch tail. (History: at $5700, then $5F00, then packed to
    # $5F70 on 2026-09-08; then moved OUT of the $5F00 page entirely on 2026-09-08
    # so the OS image -- which grows to hold the OUTCH->window sink -- can use the
    # whole $5F00..$5FFF page. They alias APBUF ($6800, the ">>" redirect-append
    # buffer, 512 B) because the two are DISJOINT IN TIME: completion runs only in
    # the interactive line editor at the prompt, the append buffer only during a
    # redirect flush -- never both at once, and no program is loaded in either
    # case. Sizes: CMPPFX 64, CMPLCP 16, CMPDIR 64 -- all NUL-terminated and
    # bounded by the 64-byte LINEBUF, so a word/leaf is <=63.)
    ('shell completion', 'CMPPFX', 0x5C00, 'tab-complete: leaf prefix being completed (NUL-term, 64; aliases APBUF)'),
    ('shell completion', 'CMPLCP', 0x5C40, 'tab-complete: longest common prefix of the matches (NUL-term, 16; aliases APBUF)'),
    ('shell completion', 'CMPDIR', 0x5C50, 'tab-complete: directory-part path string, for CDPATH (NUL-term, 64; aliases APBUF)'),
    ('shell completion', 'CMPPL', 0x6091, 'tab-complete: length of the typed leaf prefix'),
    ('shell completion', 'CMPCNT', 0x6092, 'tab-complete: number of matches (saturates at 255)'),
    ('shell completion', 'CMPFW', 0x6093, 'tab-complete: 1 = completing the command word (first word)'),
    ('shell completion', 'CMPTABF', 0x6094, 'tab-complete: 1 = the previous key was a no-progress Tab'),
    ('shell completion', 'CMPISD', 0x6095, 'tab-complete: 1 = the sole match is a directory'),
    ('shell completion', 'CMPLM', 0x6096, 'tab-complete: 1 = scan in list mode (print matches)'),
    ('shell completion', 'CMPDL', 0x6097, 'tab-complete: target directory start LBA, low byte'),
    ('shell completion', 'CMPDLH', 0x6098, 'tab-complete: target directory start LBA, high byte'),
    ('shell completion', 'CMPDN', 0x6099, 'tab-complete: target directory sector count'),
    ('shell completion', 'CMPCUR', 0x609A, 'tab-complete: saved line length (cursor) across the scan'),
    ('shell completion', 'CMPSAV', 0x609B, 'tab-complete: saved SBUF entry cursor across a candidate (2)'),
    ('shell completion', 'CMPWLB', 0x609D, 'tab-complete: directory-walk running sector LBA (2)'),
    ('shell completion', 'CMPWSC', 0x609F, 'tab-complete: directory-walk sectors remaining'),
    ('shell completion', 'CMPIX', 0x60A0, 'tab-complete: KWTAB index during the built-in scan'),

    # Console (tty) state for the BIOS PUTC. P8X emits a bare LF for a newline
    # (p8cc's puts -> LDA #10), which only renders correctly if something adds the
    # CR. Under the emulator the host tty does it (ONLCR); on a real serial link
    # nothing does, and the output staircases. PUTC now performs that expansion,
    # which is the same place Unix puts it -- on the terminal device, so file and
    # pipe output (which never reaches CONOUT) stays clean single-byte LF.
    ('console tty state', 'TTYRAW', 0x60A1, '0 = expand a bare LF to CR LF on console output; nonzero = pass bytes through untouched (for binary over the serial link, like stty raw)'),
    ('console tty state', 'TTYLST', 0x60A2, 'last byte PUTC transmitted, so an LF that already follows a CR is not doubled'),
    ('console tty state', 'TTYCH', 0x60A3, "PUTC's saved character (PUTC must preserve A)"),

    # graphics presence: probed once by the monitor at wake (GLID=='G' at $FF54),
    # re-affirmed by the OS at boot, read by every GL program via has_graphics().
    # This is the two-mode selector: headless serial console vs. graphics desktop
    # (see docs/p8x-two-mode-design.md). One shared byte across monitor + OS + programs.
    ('graphics presence', 'GFXPRES', 0x60A4, '1 = GL card fitted (screen is the display); 0 = headless serial console'),

    # glass TTY (two-mode P2): the on-screen text console behind BIOS CONOUT.
    # When GFXPRES and not GTSUSP, CONOUT draws each byte to the GL screen (via GL
    # TEXT) as well as the serial ACIA. Cursor is (col,row); clear-on-full MVP (no
    # framebuffer). Shared monitor + OS state. See docs/p8x-two-mode-design.md.
    ('glass tty', 'GTCOL', 0x60A5, 'glass TTY cursor column (0..GTCOLS-1)'),
    ('glass tty', 'GTROW', 0x60A6, 'glass TTY cursor row (0..GTROWS-1)'),
    ('glass tty', 'GTSUSP', 0x60A7, 'nonzero = glass TTY suspended (a full-screen GL app owns the screen; CONOUT is serial-only)'),
    ('glass tty', 'GCONEN', 0x60AF, '1 = glass TTY console ENABLED (CONOUT mirrors to the GL screen); 0 = off (serial-only, the default -- `screen on` enables it)'),
    ('glass tty', 'GTXL', 0x60A8, 'glass TTY cursor pixel x, low byte (0..474, step 6)'),
    ('glass tty', 'GTXH', 0x60A9, 'glass TTY cursor pixel x, high byte'),
    ('glass tty', 'GTYL', 0x60AA, 'glass TTY text-baseline pixel y (window, y-up), low byte'),
    ('glass tty', 'GTYH', 0x60AB, 'glass TTY text-baseline pixel y, high byte'),
    ('glass tty', 'GTCH', 0x60AC, 'glass TTY: the byte currently being drawn'),
    ('glass tty', 'GTTMP', 0x60AD, 'glass TTY: FIFO-push scratch (holds the byte across the backpressure wait)'),
    ('glass tty', 'GTCNT', 0x60AE, 'glass TTY: table-stream byte counter'),
]

HERE = os.path.dirname(os.path.abspath(__file__))

def _emit(path, header, fmt, comment):
    out, cur = [header, ""], None
    for sec, name, val, cmt in MAP:
        if sec != cur: out += ["", comment(sec)]; cur = sec
        line = fmt(name, val)
        if cmt: line = "%-32s %s" % (line, comment(cmt))
        out.append(line)
    open(os.path.join(HERE, path), "w").write("\n".join(out) + "\n")
    print("wrote generators/%s (%d symbols)" % (path, len(MAP)))

def main():
    _emit("memmap.inc",
          "; memmap.inc - GENERATED by generators/gen_memmap.py. Do not edit.\n"
          "; P8X data memory map as asm equates; .include from firmware / os / p8xcc.",
          lambda n, v: "%-11s = $%04X" % (n, v), lambda s: "; " + s)
    _emit("memmap.h",
          "/* memmap.h - GENERATED by generators/gen_memmap.py. Do not edit. */\n"
          "#ifndef P8X_MEMMAP_H\n#define P8X_MEMMAP_H",
          lambda n, v: "#define %-11s 0x%04X" % (n, v), lambda s: "/* %s */" % s)
    open(os.path.join(HERE, "memmap.h"), "a").write("\n#endif\n")
    _emit("memmap.py",
          "# memmap.py - GENERATED by generators/gen_memmap.py. Do not edit.",
          lambda n, v: "%-11s = 0x%04X" % (n, v), lambda s: "# " + s)

if __name__ == "__main__":
    main()
