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
    ('memory-region anchors', 'TPABASE', 0x6A00, 'transient program area base (RUNnable programs load here)'),
    ('memory-region anchors', 'CSTACKTOP', 0xF800, 'compiler C-stack top (grows down; p8cc __csp init)'),
    ('I/O ports ($FF00-$FFFF)', 'ACIAS', 0xFF04, 'ACIA status (rd) / control (wr)'),
    ('I/O ports ($FF00-$FFFF)', 'ACIAD', 0xFF05, 'ACIA data'),
    ('I/O ports ($FF00-$FFFF)', 'CFDATA', 0xFF10, 'CF task file'),
    ('I/O ports ($FF00-$FFFF)', 'CFFEAT', 0xFF11, ''),
    ('I/O ports ($FF00-$FFFF)', 'CFSCNT', 0xFF12, ''),
    ('I/O ports ($FF00-$FFFF)', 'CFLBA0', 0xFF13, ''),
    ('I/O ports ($FF00-$FFFF)', 'CFLBA1', 0xFF14, ''),
    ('I/O ports ($FF00-$FFFF)', 'CFLBA2', 0xFF15, ''),
    ('I/O ports ($FF00-$FFFF)', 'CFHEAD', 0xFF16, '$E0 = LBA mode, drive 0'),
    ('I/O ports ($FF00-$FFFF)', 'CFCMD', 0xFF17, 'command (wr) / status (rd)'),
    ('I/O ports ($FF00-$FFFF)', 'CFSTAT', 0xFF17, ''),

    # Graphics display (GPU). 480x272 RGB565 direct colour -- a pixel IS its
    # colour, no palette, no modes (stage 6) -- framebuffer in the in-package
    # SDRAM behind the streaming controller. The engine lives in the DEVICE,
    # not in software: BASIC loads the coordinate registers and writes GCMD, so
    # a filled box is ~8 port writes instead of a quarter-million through a
    # data port. Coordinates are 16-bit low/high pairs (see the high bytes
    # below); anything off-screen is discarded per pixel (see gpu_px in the
    # emulator) rather than clipped, so the C and Verilog models agree without
    # a clipping algorithm.
    # $F0 SELFTEST also exists, but only in the emulator -- the RTL rejects it
    # and sets GSTAT's ERR bit, so it is deliberately left off the GCMD list
    # below rather than advertised as something the board will do.
    ('I/O ports ($FF00-$FFFF)', 'GX0', 0xFF20, 'draw X0 (0-479)'),
    ('I/O ports ($FF00-$FFFF)', 'GY0', 0xFF21, 'draw Y0 (0-271)'),
    ('I/O ports ($FF00-$FFFF)', 'GX1', 0xFF22, 'draw X1 (0-479)'),
    ('I/O ports ($FF00-$FFFF)', 'GY1', 0xFF23, 'draw Y1 (0-271)'),
    ('I/O ports ($FF00-$FFFF)', 'GCOL', 0xFF24, 'pen LOW byte -- the pen is a whole RGB565 colour (see GCOLH)'),
    ('I/O ports ($FF00-$FFFF)', 'GCMD', 0xFF25, 'write executes: 1 PLOT 2 LINE 3 BOX 4 BOXFILL 5 CLS 7 CIRCLE 8 CIRCLEFILL 9 POINT A ELLIPSE B ELLIPSEFILL / F1 RESET F2 IDENT'),
    ('I/O ports ($FF00-$FFFF)', 'GSTAT', 0xFF26, 'read: bit7 BUSY, bit0 ERR (unknown command)'),
    ('I/O ports ($FF00-$FFFF)', 'GDATA', 0xFF27, 'read: IDENT record stream, else the last POINT result'),
    ('I/O ports ($FF00-$FFFF)', 'GPARM', 0xFF28, 'scalar argument: CIRCLE/ELLIPSE x-radius'),
    # Coordinate HIGH bytes. Writing a low byte CLEARS its high byte, so software
    # that never touches these cannot be broken by a stale one; write the high
    # byte after the low when a coordinate exceeds 255. They are not optional
    # any more: the panel is 480 wide, so 9 bits of X are needed to reach the
    # right-hand edge at all.
    ('I/O ports ($FF00-$FFFF)', 'GX0H', 0xFF29, 'X0 high byte (write AFTER GX0)'),
    ('I/O ports ($FF00-$FFFF)', 'GY0H', 0xFF2A, 'Y0 high byte (write AFTER GY0)'),
    ('I/O ports ($FF00-$FFFF)', 'GX1H', 0xFF2B, 'X1 high byte (write AFTER GX1)'),
    ('I/O ports ($FF00-$FFFF)', 'GY1H', 0xFF2C, 'Y1 high byte (write AFTER GY1)'),
    # Presence signature. An absent card floats the bus to $FF, so a single magic
    # byte is not enough to detect one; two fixed bytes at fixed addresses are.
    ('I/O ports ($FF00-$FFFF)', 'GMODE', 0xFF2E, 'write: pixel-write mode (stage 10f LINFUN) -- 0 replace, 1 complement, 2 OR, 3 AND, 4 XOR; applies to lines/points/outlines, fills always replace; 5-7 act as replace. GID1 keeps the read side'),
    ('I/O ports ($FF00-$FFFF)', 'GID0', 0xFF2D, "read: $50 'P' -- card-presence signature"),
    # The register page is FULL, and GID0/GID1 are read-only -- their write
    # decodes are the only spare corners. GCOLH takes $FF2D's write side so a
    # pen can carry a whole RGB565 colour; $FF2E's write side stays free.
    ('I/O ports ($FF00-$FFFF)', 'GCOLH', 0xFF2D, 'write: pen HIGH byte (write AFTER GCOL; a GCOL write clears it)'),
    ('I/O ports ($FF00-$FFFF)', 'GID1', 0xFF2E, "read: $47 'G' -- with GID0 spells PG"),
    ('I/O ports ($FF00-$FFFF)', 'GPARM2', 0xFF2F, 'ELLIPSE y-radius (GPARM is the x-radius)'),

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
    ('shared sector buffer', 'SBUF', 0x6100, 'sector buffer'),
    ('hardware stack', 'STKTOP', 0xFEFF, ''),
    ('BIOS / FS scratch ($6000-$60FF)', 'ROSTAT', 0x605E, 'read-stream state base (ROLBA..ROCNT, 11 bytes)'),
    ('OS scratch ($6300-$69FF)', 'LINEBUF', 0x6300, 'shell input line (64 bytes)'),
    ('OS scratch ($6300-$69FF)', 'CMDBUF', 0x6340, 'parsed command word (16 bytes)'),
    ('OS scratch ($6300-$69FF)', 'NAMEBUF', 0x6350, '12-byte filename (search key / DIR scratch)'),
    ('OS scratch ($6300-$69FF)', 'ECNT', 0x6363, 'entries-left-in-sector counter'),
    ('OS scratch ($6300-$69FF)', 'FLAGS', 0x6364, 'current entry flag byte'),
    ('OS scratch ($6300-$69FF)', 'MATCH', 0x6365, '1 = name matched / strings equal'),
    ('OS scratch ($6300-$69FF)', 'LENLO', 0x6366, 'entry length, low 16 bits'),
    ('OS scratch ($6300-$69FF)', 'LENHI', 0x6367, ''),
    ('OS scratch ($6300-$69FF)', 'STARTLO', 0x6368, 'entry start LBA (low byte)'),
    ('OS scratch ($6300-$69FF)', 'LOADLO', 0x6369, 'entry load address'),
    ('OS scratch ($6300-$69FF)', 'LOADHI', 0x636A, ''),
    ('OS scratch ($6300-$69FF)', 'EXECLO', 0x636B, 'entry exec address'),
    ('OS scratch ($6300-$69FF)', 'EXECHI', 0x636C, ''),
    ('OS scratch ($6300-$69FF)', 'DLBA', 0x636D, 'directory sector being scanned'),
    ('OS scratch ($6300-$69FF)', 'SECCNT', 0x636E, 'sectors left to transfer'),
    ('OS scratch ($6300-$69FF)', 'CURLBA', 0x636F, 'current data LBA'),
    ('OS scratch ($6300-$69FF)', 'ENTPL', 0x6370, 'pointer to a directory entry (in SBUF):'),
    ('OS scratch ($6300-$69FF)', 'ENTPH', 0x6371, 'flag byte for DEL, entry start for SAVE'),
    ('OS scratch ($6300-$69FF)', 'ARGPL', 0x6372, 'saved arg position in LINEBUF'),
    ('OS scratch ($6300-$69FF)', 'ARGPH', 0x6373, ''),
    ('OS scratch ($6300-$69FF)', 'HXLO', 0x6374, 'GETHEX result'),
    ('OS scratch ($6300-$69FF)', 'HXHI', 0x6375, ''),
    ('OS scratch ($6300-$69FF)', 'DIGIT', 0x6376, 'HEXVAL digit value'),
    ('OS scratch ($6300-$69FF)', 'SHCNT', 0x6377, 'shift counter'),
    ('OS scratch ($6300-$69FF)', 'SVSTLO', 0x6378, 'SAVE source start address'),
    ('OS scratch ($6300-$69FF)', 'SVSTHI', 0x6379, ''),
    ('OS scratch ($6300-$69FF)', 'FREELO', 0x637A, 'boot-block free pointer (next data LBA)'),
    ('OS scratch ($6300-$69FF)', 'FREEHI', 0x637B, ''),
    ('OS scratch ($6300-$69FF)', 'SRCLO', 0x637C, 'running source pointer during the copy'),
    ('OS scratch ($6300-$69FF)', 'SRCHI', 0x637D, ''),
    ('OS scratch ($6300-$69FF)', 'REM', 0x637E, 'sectors remaining in the SAVE write loop'),
    ('OS scratch ($6300-$69FF)', 'NF', 0x6380, 'running next-free LBA'),
    ('OS scratch ($6300-$69FF)', 'PFOUND', 0x6381, '1 if this pass found an unpacked extent'),
    ('OS scratch ($6300-$69FF)', 'MINSTRT', 0x6382, 'smallest start LBA >= NF this pass'),
    ('OS scratch ($6300-$69FF)', 'MINSEC', 0x6383, "that extent's sector count"),
    ('OS scratch ($6300-$69FF)', 'MINPL', 0x6384, "pointer to that entry's start-LBA field (in SBUF)"),
    ('OS scratch ($6300-$69FF)', 'MINPH', 0x6385, ''),
    ('OS scratch ($6300-$69FF)', 'MINDL', 0x6386, "that entry's directory sector LBA"),
    ('OS scratch ($6300-$69FF)', 'ESTART', 0x6387, 'current entry start LBA (low byte)'),
    ('OS scratch ($6300-$69FF)', 'SRCL', 0x6388, 'copy source LBA'),
    ('OS scratch ($6300-$69FF)', 'DSTL', 0x6389, 'copy dest LBA'),
    ('OS scratch ($6300-$69FF)', 'CPYN', 0x638A, 'sectors left to copy'),
    ('OS scratch ($6300-$69FF)', 'CANDL', 0x638B, "current entry's start-field pointer"),
    ('OS scratch ($6300-$69FF)', 'CANDH', 0x638C, ''),
    ('OS scratch ($6300-$69FF)', 'ROOTN', 0x638D, 'root directory sector count (4)'),
    ('OS scratch ($6300-$69FF)', 'DATABASE', 0x638E, 'first data LBA (37)'),
    ('OS scratch ($6300-$69FF)', 'CWDL', 0x638F, 'current directory: start LBA'),
    ('OS scratch ($6300-$69FF)', 'CWDN', 0x6390, 'sector count'),
    ('OS scratch ($6300-$69FF)', 'SDIRL', 0x6391, 'directory being scanned this op (start LBA)'),
    ('OS scratch ($6300-$69FF)', 'SDIRN', 0x6392, 'sector count'),
    ('OS scratch ($6300-$69FF)', 'SCNT', 0x6393, 'sectors-left counter while scanning a directory'),
    ('OS scratch ($6300-$69FF)', 'LSL', 0x6394, "SETPATH: pointer to the last '/' in CWDPATH"),
    ('OS scratch ($6300-$69FF)', 'LSH', 0x6395, ''),
    ('OS scratch ($6300-$69FF)', 'PATHL', 0x6396, 'saved path cursor across DESCEND (FINDENT clobbers P2)'),
    ('OS scratch ($6300-$69FF)', 'PATHH', 0x6397, ''),
    ('OS scratch ($6300-$69FF)', 'NEWLBA', 0x6398, 'MKDIR: LBA of the new directory extent'),
    ('OS scratch ($6300-$69FF)', 'PSL', 0x6399, 'MKDIR: parent dir start LBA / sector count'),
    ('OS scratch ($6300-$69FF)', 'PSN', 0x639A, ''),
    ('OS scratch ($6300-$69FF)', 'EFLAG', 0x639B, 'flag byte WRENT stamps (F_FILE for SAVE, F_DIR for MKDIR)'),
    ('OS scratch ($6300-$69FF)', 'RMDL', 0x639C, 'RMDIR: parent directory sector holding the entry'),
    ('OS scratch ($6300-$69FF)', 'CDST', 0x639D, 'current directory: start LBA / sectors / entry index'),
    ('OS scratch ($6300-$69FF)', 'CDSC', 0x639E, ''),
    ('OS scratch ($6300-$69FF)', 'CIDX', 0x639F, ''),
    ('OS scratch ($6300-$69FF)', 'REDIRF', 0x63A0, '0 = console, 1 = capturing to RBUF'),
    ('OS scratch ($6300-$69FF)', 'RCH', 0x63A1, 'OUTCH: byte being emitted'),
    ('OS scratch ($6300-$69FF)', 'RS2L', 0x63A2, 'OUTCH: saved caller P2'),
    ('OS scratch ($6300-$69FF)', 'RS2H', 0x63A3, ''),
    ('OS scratch ($6300-$69FF)', 'RPTRL', 0x63A4, 'OUTCH: next free byte in the capture buffer'),
    ('OS scratch ($6300-$69FF)', 'RPTRH', 0x63A5, ''),
    ('OS scratch ($6300-$69FF)', 'RHX', 0x63A6, 'OPHEX8 scratch'),
    ('OS scratch ($6300-$69FF)', 'REDNAME', 0x63A7, 'redirect target filename (null-terminated, <=48): $63A7..$63D6'),
    ('OS scratch ($6300-$69FF)', 'FNDIR', 0x63D7, 'directories counted'),
    ('OS scratch ($6300-$69FF)', 'FNFIL', 0x63D8, 'files counted'),
    ('OS scratch ($6300-$69FF)', 'FNDEL', 0x63D9, 'deleted slots counted'),
    ('OS scratch ($6300-$69FF)', 'FMAXE', 0x63DA, 'highest extent end LBA seen (data area only)'),
    ('OS scratch ($6300-$69FF)', 'FUSED', 0x63DB, 'data sectors occupied by live extents'),
    ('OS scratch ($6300-$69FF)', 'FERR', 0x63DC, 'problems found (0 = clean)'),
    ('OS scratch ($6300-$69FF)', 'FCHILD', 0x63DD, "CHKDD: directory whose '..' is being checked"),
    ('OS scratch ($6300-$69FF)', 'FEXP', 0x63DE, 'CHKDD: expected parent LBA'),
    ('TPA (transient programs)', 'RBUF', 0x6A00, 'capture buffer = the TPA (free during a built-in cmd)'),
    ('OS scratch ($6300-$69FF)', 'TSP', 0x63E0, 'tree stack depth (0 = at root level)'),
    ('OS scratch ($6300-$69FF)', 'TI', 0x63E1, 'scratch loop counter for the frame stack'),
    ('OS scratch ($6300-$69FF)', 'LENHI2', 0x63E2, 'entry length, bits 16..23 (the BIOS FLEN 3rd byte)'),
    ('OS scratch ($6300-$69FF)', 'SECCH', 0x63E3, 'SECCOUNT sector-count high byte (files >255 sectors)'),
    ('OS scratch ($6300-$69FF)', 'MINSECH', 0x63E4, "PACK: chosen extent's sector count, high byte"),
    ('OS scratch ($6300-$69FF)', 'CPYNH', 0x63E5, 'PK2MOVE: sectors-to-copy counter, high byte'),
    ('OS scratch ($6300-$69FF)', 'TFRAME', 0x64B7, '8 frames x 4 bytes (dst_lo,dst_hi,dsc,idx): $64B7..$64D6'),
    ('OS scratch ($6300-$69FF)', 'PPSEC', 0x63FA, "chosen extent's parent-entry: dir sector LBA / slot"),
    ('OS scratch ($6300-$69FF)', 'PPSLOT', 0x63FB, ''),
    ('OS scratch ($6300-$69FF)', 'CANDSEC', 0x63FC, "candidate entry's location during the find walk"),
    ('OS scratch ($6300-$69FF)', 'CANDSLOT', 0x63FD, ''),
    ('OS scratch ($6300-$69FF)', 'PARST', 0x63FE, "PK2FIX: parent directory start LBA (for '..')"),
    ('OS scratch ($6300-$69FF)', 'CWDPATH', 0x6400, 'textual CWD path for the prompt (up to 48 bytes)'),
    ('OS scratch ($6300-$69FF)', 'INMODE', 0x6430, 'SYS_GETC source: 0 = console, 1 = the read stream'),
    ('OS scratch ($6300-$69FF)', 'INARM', 0x6431, "shell armed a '< file' for the next RUN"),
    ('OS scratch ($6300-$69FF)', 'INNAME', 0x6432, "'< file' name (null-terminated, <=48): $6432..$6461"),
    ('OS scratch ($6300-$69FF)', 'PIPEF', 0x6462, 'pipe stage: 0 none, 1 left ran, 2 right ran'),
    ('OS scratch ($6300-$69FF)', 'PIPEBUF', 0x6463, "saved right-hand command of a 'cmd | cmd' ($6463..$64A2)"),
    ('OS scratch ($6300-$69FF)', 'CWDLH', 0x64A3, 'CWDL high byte (current working directory start LBA)'),
    ('OS scratch ($6300-$69FF)', 'SDIRLH', 0x64A4, 'SDIRL high byte (directory being scanned this op)'),
    ('OS scratch ($6300-$69FF)', 'STARTHI', 0x64A5, 'STARTLO high byte (entry start LBA from FINDENT)'),
    ('OS scratch ($6300-$69FF)', 'DLBAH', 0x64A6, 'DLBA high byte (directory-sector scan cursor)'),
    ('OS scratch ($6300-$69FF)', 'NEWLBAH', 0x64A7, 'NEWLBA high byte (MKDIR new extent)'),
    ('OS scratch ($6300-$69FF)', 'PSLH', 0x64A8, 'PSL high byte (MKDIR parent extent)'),
    ('OS scratch ($6300-$69FF)', 'PARSTH', 0x64A9, "PARST high byte (PACK '..' parent fix)"),
    ('OS scratch ($6300-$69FF)', 'RMDLH', 0x64AA, 'RMDL high byte (RMDIR parent sector)'),
    ('OS scratch ($6300-$69FF)', 'CURLBAH', 0x64AB, 'CURLBA high byte (SAVE data-write LBA, 16-bit)'),
    ('OS scratch ($6300-$69FF)', 'NFH', 0x64AC, 'NF high byte (PACK next-free target)'),
    ('OS scratch ($6300-$69FF)', 'MINSTRTH', 0x64AD, 'MINSTRT high byte (smallest start LBA this pass)'),
    ('OS scratch ($6300-$69FF)', 'CDSTH', 0x64AE, 'CDST high byte (current directory in the walk)'),
    ('OS scratch ($6300-$69FF)', 'CANDSECH', 0x64AF, "CANDSEC high byte (candidate entry's dir sector)"),
    ('OS scratch ($6300-$69FF)', 'PPSECH', 0x64B0, "PPSEC high byte (chosen extent's parent-entry sector)"),
    ('OS scratch ($6300-$69FF)', 'SRCH', 0x64B1, 'SRCL high byte (PK2MOVE copy source)'),
    ('OS scratch ($6300-$69FF)', 'DSTH', 0x64B2, 'DSTL high byte (PK2MOVE copy dest)'),
    ('OS scratch ($6300-$69FF)', 'FCHILDH', 0x64B3, 'FCHILD high byte (CHKDD child dir)'),
    ('OS scratch ($6300-$69FF)', 'FEXPH', 0x64B4, 'FEXP high byte (CHKDD expected parent)'),
    ('OS scratch ($6300-$69FF)', 'FMAXEH', 0x64B5, 'FMAXE high byte (FSCK highest extent end)'),
    ('OS scratch ($6300-$69FF)', 'FUSEDH', 0x64B6, 'FUSED high byte (FSCK live data sectors)'),
    ('OS scratch ($6300-$69FF)', 'REDAPP', 0x64D7, '>> append redirect: 1 = prepend the existing file'),
    ('OS scratch ($6300-$69FF)', 'APHAVE', 0x64D8, '>> : 1 = an existing file to prepend was found'),
    ('OS scratch ($6300-$69FF)', 'APLBA', 0x64D9, ">> : old file's start LBA (2 bytes)"),
    ('OS scratch ($6300-$69FF)', 'APREM', 0x64DB, '>> : old file bytes left to copy (2 bytes)'),
    ('OS scratch ($6300-$69FF)', 'APCHK', 0x64DD, '>> : bytes to emit from the current sector (2 bytes)'),
    ('OS scratch ($6300-$69FF)', 'SCRIPTM', 0x64E0, '1 = the shell is running lines from a `sh` script'),
    ('OS scratch ($6300-$69FF)', 'SCRSAVE', 0x64E1, 'saved script read-stream state (ROSTATE 13 + ROSDRV = 14: $64E1..$64EE)'),
    ('OS scratch ($6300-$69FF)', 'SCRCNT', 0x64EF, 'byte counter for SAVESCR/RESTSCR (1)'),
    ('OS scratch ($6300-$69FF)', 'APBUF', 0x6800, '>> prepend sector buffer (512B, below the TPA); also the'),
    ('OS scratch ($6300-$69FF)', 'IBUF', 0x6500, '512-byte buffer for the stdin read stream'),
    ('OS scratch ($6300-$69FF)', 'PATHBUF', 0x6700, "search path, ';'-separated dirs; default '/BIN' ($6700..$673F)"),
    ('OS scratch ($6300-$69FF)', 'RUNPATH', 0x6740, 'scratch: candidate program path built during a lookup ($6740..$679F)'),
    ('OS scratch ($6300-$69FF)', 'RUNSKIP', 0x67A0, 'DORUN: 1 = skip the program-name word for the arg pointer'),
    ('OS scratch ($6300-$69FF)', 'PSCANL', 0x67A1, 'PATH search cursor into PATHBUF (low)'),
    ('OS scratch ($6300-$69FF)', 'PSCANH', 0x67A2, 'PATH search cursor into PATHBUF (high)'),
    ('OS scratch ($6300-$69FF)', 'GPLF', 0x67A3, 'SYS_GETC console: 1 = a LF is pending after a CR keypress'),
    ('OS scratch ($6300-$69FF)', 'CURDRIVE', 0x67A4, 'derived: 1 if the CWD is under /d1 (drive 1), else 0'),
    ('OS scratch ($6300-$69FF)', 'DRVINIT', 0x67A5, "bitmask: bit N set = drive N has been CFINIT'd this session"),
    ('OS scratch ($6300-$69FF)', 'MPSAV', 0x67A6, "MNTPFX: saved P2 (2 bytes) while sniffing a 'd1' prefix"),
    # Command-line history (interactive line editor). The ring lives in the free
    # RAM gap between the OS image end (~$4900) and the $6000 scratch band; 32
    # slots x 64 bytes fills $5800..$5FFF exactly. State bytes sit in the free
    # tail of the $6000 FS-scratch page (after CNTW).
    ('shell history', 'HISTST', 0x608E, 'history ring: index where the next entry is written (0..HISTN-1)'),
    ('shell history', 'HISTCT', 0x608F, 'history ring: number of stored entries (0..HISTN)'),
    ('shell history', 'HISTNV', 0x6090, 'history ring: recall cursor (0 = not navigating; N = N lines back)'),
    ('shell history', 'HISTRING', 0x5800, 'history ring buffer base: HISTN x HISTLEN bytes ($5800..$5FFF)'),
    # Tab autocomplete scratch (interactive line editor). Buffers in the free gap
    # below the history ring; state bytes in the $6000 FS-scratch tail.
    ('shell completion', 'CMPPFX', 0x5700, 'tab-complete: leaf prefix being completed (NUL-term)'),
    ('shell completion', 'CMPLCP', 0x5740, 'tab-complete: longest common prefix of the matches (NUL-term)'),
    ('shell completion', 'CMPDIR', 0x5760, 'tab-complete: directory-part path string, for CDPATH (NUL-term)'),
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
